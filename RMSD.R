# ============================================================
# RMSD 통합 분석 스크립트
# 작성: Hoon
#
# [목적]
#   md_simulation/RMSD/날짜폴더 안에 있는 RMSD .dat 파일들을 모두 읽어서
#   1) 구조별 패널 분리형 그래프
#   2) 구조별 평균 비교형 그래프
#   를 자동 생성한다.
#
# [입력 파일명 규칙]
#   YYYY-MM-DD_STRUCTURE[_SUBTYPE]_rX_RMSD.dat
#
# 예:
#   2026-04-20_NPG6-4_r1_RMSD.dat
#   2026-04-20_NPG6-4_A3a_r1_RMSD.dat
#
# [중요한 파일명 해석 규칙]
#   - 첫 번째 항목 = 날짜
#   - 마지막 r숫자 = replicate
#   - 그 사이 첫 번째 이름 = main structure
#   - 그 사이 추가 이름 = subtype
#
# 예:
#   2026-04-20_NPG6-4_r1_RMSD.dat
#     main structure = NPG6-4
#     subtype        = 없음
#
#   2026-04-20_NPG6-4_A3a_r1_RMSD.dat
#     main structure = NPG6-4
#     subtype        = A3a
#
# [패널 표시]
#   subtype이 없으면:
#     ┌────────┐
#     │ NPG6-4 │
#     └────────┘
#
#   subtype이 있으면:
#     ┌────────┐
#     │ NPG6-4 │
#     ├────────┤
#     │ A3a    │
#     └────────┘
#
#   즉, ggplot의 facet_grid(. ~ treatment + subtype_plot)을 사용하여
#   main structure와 subtype을 두 줄 strip으로 표시한다.
#   단, subtype이 전혀 없는 데이터셋에서는 facet_wrap(~ treatment)을 사용해
#   빈 두 번째 strip이 생기지 않도록 한다.
#
# [입력 .dat 형식]
#   # frame rmsd_ca
#   0 0.000000
#   1 3.454180
#
# [출력]
#   - YYYY-MM-DD_RMSD_facet.png
#   - YYYY-MM-DD_RMSD_mean.png
# ============================================================


# ============================================================
# [0] 패키지 설치
# 처음 한 번만 실행하면 됨. 이미 설치되어 있으면 주석 유지.
# ============================================================
# install.packages("tidyverse")
# install.packages("janitor")


# ============================================================
# [1] 패키지 로드
# ============================================================
library(tidyverse)
library(janitor)


# ============================================================
# [2] 사용자 설정값
# 대부분의 그래프 조절은 이 섹션에서 하면 됨.
# ============================================================

target_folder <- "2026-04-20"
# 분석할 날짜 폴더명.
# 실제로는 아래 경로를 읽음:
#   ~/Desktop/md_simulation/RMSD/2026-04-20/
#
# 주의:
#   폴더명 날짜와 파일명 날짜가 반드시 같을 필요는 없음.
#   같은 폴더 안에 들어 있는 파일을 함께 분석함.

base_dir <- "~/Desktop/md_simulation/RMSD"
# RMSD .dat 파일들이 들어 있는 상위 폴더.

output_dir <- "~/Desktop/md_simulation/RMSD"
# 결과 PNG가 저장될 상위 폴더.

time_per_frame <- 0.1
# frame을 ns로 변환하는 값.
#
# 예:
#   1000 frames = 100 ns  → 0.1
#   2000 frames = 100 ns  → 0.05
#   500 frames  = 100 ns  → 0.2
#
# time_ns = frame * time_per_frame

x_max <- 100
# x축 최대값(ns).
# 100 ns simulation이면 100.
# 200 ns simulation이면 200으로 변경.

y_min <- -0.5
y_max <- 30.5
# y축 범위.
# RMSD가 더 높으면 y_max를 40 또는 50으로 변경.

y_break_step <- 5
# y축 눈금 간격.
# 5면 0, 5, 10, 15, 20, 25, 30.

ref_line_y <- 10
# 검은 점선 기준선 위치.
# 필요 없으면 아래 plot 코드의 geom_hline 부분을 주석 처리하면 됨.

save_excel <- FALSE
# TRUE로 바꾸면 정리된 table을 xlsx로 저장하도록 확장 가능.
# 현재는 파일이 많아지는 것을 막기 위해 FALSE 기본값.

facet_height <- 6
facet_width_per_panel <- 3.8
# 패널 분리형 그림 크기.
# 구조/subtype이 많아질수록 전체 width를 자동으로 늘림.
# 예: 패널 10개면 약 38 inch 폭으로 저장됨.
#
# 너무 넓으면 facet_width_per_panel을 3.0 정도로 줄일 수 있음.

mean_width <- 7.2
mean_height <- 6
# 평균 비교형 그래프 크기.
# legend가 오른쪽에 있으므로 전체 이미지는 약간 넓게 저장.
# 실제 plot panel은 aspect.ratio = 1로 square 유지.

line_alpha_replicate <- 0.22
line_width_replicate <- 0.30
line_width_mean <- 1.15
# 선 두께 조절.
# replicate 선이 너무 진하면 alpha를 낮추거나 linewidth를 줄이면 됨.

base_palette <- c(
  "salmon", "steelblue", "forestgreen", "purple",
  "orange", "brown", "darkcyan", "magenta", "grey40", "goldenrod"
)
# 구조/variant 수가 늘어나면 위 색상을 반복해서 사용.


# ============================================================
# [3] 공통 함수
# ============================================================

read_dat <- function(path) {
  # Desmond 추출 .dat 파일 읽기
  # header 예: "# frame rmsd_ca"
  lines <- readLines(path)

  header_idx <- which(str_starts(lines, "\\s*#"))[1]
  if (is.na(header_idx)) {
    stop(paste("헤더 줄(# frame rmsd_ca)을 찾을 수 없습니다:", path))
  }

  col_names <- lines[header_idx] |>
    str_remove("^\\s*#\\s*") |>
    str_split("\\s+") |>
    pluck(1) |>
    str_to_lower() |>
    str_replace_all("[^a-z0-9_]", "_")

  data_lines <- lines[(header_idx + 1):length(lines)]
  data_lines <- data_lines[str_detect(data_lines, "\\S")]

  read_table(
    I(data_lines),
    col_names = col_names,
    col_types = cols(.default = col_double()),
    show_col_types = FALSE
  )
}


parse_metadata <- function(filename, analysis_tag = "RMSD") {
  # 파일명에서 date, treatment, subtype, replicate를 추출.
  #
  # 입력 예:
  #   2026-04-20_NPG6-4_A3a_r1_RMSD.dat
  #
  # 결과:
  #   file_date = 2026-04-20
  #   treatment = NPG6-4
  #   subtype   = A3a
  #   replicate = r1

  name <- basename(filename)
  name <- str_remove(name, "\\.(dat|csv|xlsx)$")
  name <- str_remove(name, paste0("_", analysis_tag, "$"))

  parts <- str_split(name, "_", simplify = FALSE)[[1]]

  file_date <- parts[1]
  rep_idx <- which(str_detect(parts, "^r[0-9]+$"))

  if (length(rep_idx) == 0) {
    stop(paste("파일명에서 replicate(r1, r2 등)를 찾지 못했습니다:", filename))
  }

  rep_idx <- rep_idx[length(rep_idx)]
  replicate <- parts[rep_idx]

  structure_parts <- parts[2:(rep_idx - 1)]

  if (length(structure_parts) < 1) {
    stop(paste("파일명에서 구조 이름을 찾지 못했습니다:", filename))
  }

  treatment <- structure_parts[1]

  if (length(structure_parts) >= 2) {
    subtype <- paste(structure_parts[-1], collapse = "_")
  } else {
    subtype <- NA_character_
  }

  tibble(
    source = basename(filename),
    file_date = file_date,
    treatment = treatment,
    subtype = subtype,
    replicate = replicate
  )
}


make_palette <- function(levels_vec) {
  # level 수에 맞춰 색상을 자동 배정.
  setNames(rep(base_palette, length.out = length(levels_vec)), levels_vec)
}


add_structure_facet <- function(p, data) {
  # subtype이 하나라도 있으면 두 줄 strip 사용:
  #   treatment / subtype
  #
  # subtype이 전혀 없으면 한 줄 strip 사용:
  #   treatment
  #
  # strip text는 theme에서 중앙 정렬(hjust = 0.5)함.

  if (any(!is.na(data$subtype) & data$subtype != "")) {
    p + facet_grid(. ~ treatment + subtype_plot, scales = "fixed")
  } else {
    p + facet_wrap(~ treatment, scales = "fixed", nrow = 1)
  }
}


# ============================================================
# [4] 파일 찾기
# ============================================================

folder_path <- file.path(path.expand(base_dir), target_folder)

if (!dir.exists(folder_path)) {
  stop(paste("폴더를 찾을 수 없습니다:", folder_path))
}

all_files <- list.files(
  folder_path,
  pattern = "RMSD\\.dat$",
  full.names = TRUE,
  ignore.case = TRUE
)

if (length(all_files) == 0) {
  stop(paste("RMSD .dat 파일을 찾을 수 없습니다:", folder_path))
}

message(paste("▶ 발견된 RMSD 파일:", length(all_files), "개"))
message(paste(" ", basename(all_files), collapse = "\n  "))


# ============================================================
# [5] 데이터 읽기 + metadata 결합
# ============================================================

rmsd_data <- map_dfr(all_files, function(f) {
  meta <- parse_metadata(f, "RMSD")
  df <- read_dat(f) |> clean_names()

  df |> mutate(
    source = meta$source,
    file_date = meta$file_date,
    treatment = meta$treatment,
    subtype = meta$subtype,
    replicate = meta$replicate
  )
})

rmsd_candidates <- c("rmsd_ca", "prot_ca", "rmsd")
rmsd_col <- rmsd_candidates[rmsd_candidates %in% names(rmsd_data)][1]

if (is.na(rmsd_col) || is.null(rmsd_col)) {
  stop(paste("RMSD 컬럼을 찾을 수 없습니다. 현재 컬럼명:", paste(names(rmsd_data), collapse = ", ")))
}

rmsd_data <- rmsd_data |>
  rename(rmsd = all_of(rmsd_col)) |>
  mutate(
    frame = as.numeric(frame),
    rmsd = as.numeric(rmsd),
    time_ns = frame * time_per_frame,
    subtype_plot = if_else(is.na(subtype), "", subtype),
    variant_label = if_else(is.na(subtype), treatment, paste(treatment, subtype, sep = "_"))
  )

variant_levels <- unique(rmsd_data$variant_label)
variant_palette <- make_palette(variant_levels)

n_panels <- n_distinct(rmsd_data$variant_label)
facet_width <- max(6, facet_width_per_panel * n_panels)


# ============================================================
# [6] 출력 폴더
# ============================================================

out_dir <- file.path(path.expand(output_dir), target_folder)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)


# ============================================================
# [7] Plot 1: 패널 분리형 RMSD
# ============================================================

plot_facet_base <- ggplot(rmsd_data, aes(x = time_ns, y = rmsd)) +
  geom_hline(
    yintercept = ref_line_y,
    linetype = "dashed",
    color = "black",
    linewidth = 0.45,
    alpha = 0.8
  ) +
  geom_line(
    aes(group = source, color = variant_label),
    alpha = line_alpha_replicate,
    linewidth = line_width_replicate
  ) +
  stat_summary(
    aes(group = variant_label, color = variant_label),
    fun = mean,
    geom = "line",
    linewidth = line_width_mean
  ) +
  scale_color_manual(values = variant_palette, drop = FALSE) +
  scale_y_continuous(breaks = seq(0, y_max, by = y_break_step)) +
  coord_cartesian(xlim = c(0, x_max), ylim = c(y_min, y_max)) +
  labs(
    title = paste("Protein RMSD -", target_folder),
    x = "Time (ns)",
    y = expression(RMSD~"(" * ring(A) * ")")
  ) +
  theme_classic(base_size = 14) +
  theme(
    legend.position = "none",
    axis.line = element_line(color = "black", linewidth = 0.8),
    panel.border = element_rect(color = "black", fill = NA, linewidth = 0.8),
    strip.background = element_rect(color = "black", fill = "grey95", linewidth = 0.8),
    strip.text = element_text(face = "bold", hjust = 0.5, margin = margin(4, 4, 4, 4)),
    panel.spacing.x = unit(0.18, "lines")
  )

plot_facet <- add_structure_facet(plot_facet_base, rmsd_data)

print(plot_facet)

ggsave(
  file.path(out_dir, paste0(target_folder, "_RMSD_facet.png")),
  plot = plot_facet,
  width = facet_width,
  height = facet_height,
  dpi = 300,
  limitsize = FALSE
)


# ============================================================
# [8] Plot 2: 평균 비교형 RMSD
# ============================================================

rmsd_mean <- rmsd_data |>
  group_by(variant_label, time_ns) |>
  summarise(rmsd_mean = mean(rmsd, na.rm = TRUE), .groups = "drop")

plot_mean <- ggplot(rmsd_mean, aes(x = time_ns, y = rmsd_mean, color = variant_label)) +
  geom_hline(
    yintercept = ref_line_y,
    linetype = "dashed",
    color = "black",
    linewidth = 0.45,
    alpha = 0.8
  ) +
  geom_line(linewidth = line_width_mean) +
  scale_color_manual(values = variant_palette, drop = FALSE) +
  scale_y_continuous(breaks = seq(0, y_max, by = y_break_step)) +
  coord_cartesian(xlim = c(0, x_max), ylim = c(y_min, y_max)) +
  labs(
    title = paste("Protein RMSD Mean -", target_folder),
    x = "Time (ns)",
    y = expression(RMSD~"(" * ring(A) * ")"),
    color = NULL
  ) +
  theme_classic(base_size = 14) +
  theme(
    aspect.ratio = 1,
    legend.position = "right",
    legend.title = element_blank(),
    axis.line = element_line(color = "black", linewidth = 0.8),
    panel.border = element_rect(color = "black", fill = NA, linewidth = 0.8)
  )

print(plot_mean)

ggsave(
  file.path(out_dir, paste0(target_folder, "_RMSD_mean.png")),
  plot = plot_mean,
  width = mean_width,
  height = mean_height,
  dpi = 300
)

message(paste("✅ RMSD 완료:", out_dir))
