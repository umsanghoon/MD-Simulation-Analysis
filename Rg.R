# ============================================================
# Rg 통합 분석 스크립트
# 작성: Hoon
#
# [목적]
#   md_simulation/Rg/날짜폴더 안에 있는 Rg .dat 파일들을 모두 읽어서
#   1) 구조별 패널 분리형 그래프
#   2) 구조별 평균 비교형 그래프
#   를 자동 생성한다.
#
# [입력 파일명 규칙]
#   YYYY-MM-DD_STRUCTURE[_SUBTYPE]_rX_Rg.dat
#
# 예:
#   2026-04-20_NPG6-4_r1_Rg.dat
#   2026-04-20_NPG6-4_A3a_r1_Rg.dat
#
# [패널 표시]
#   subtype 없음: NPG6-4 한 줄 strip
#   subtype 있음: NPG6-4 / A3a 두 줄 strip
# ============================================================


# ============================================================
# [0] 패키지 설치
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
# ============================================================

target_folder <- "2026-04-20"

base_dir <- "~/Desktop/md_simulation/Rg"
output_dir <- "~/Desktop/md_simulation/Rg"

time_per_frame <- 0.1
x_max <- 100

y_min <- -0.5
y_max <- 30.5
y_break_step <- 5

ref_line_y <- 10
# Rg에서는 기준선이 필요 없으면 아래 plot 코드의 geom_hline을 주석 처리해도 됨.

save_excel <- FALSE

facet_height <- 6
facet_width_per_panel <- 3.8

mean_width <- 7.2
mean_height <- 6

line_alpha_replicate <- 0.22
line_width_replicate <- 0.30
line_width_mean <- 1.15

base_palette <- c(
  "salmon", "steelblue", "forestgreen", "purple",
  "orange", "brown", "darkcyan", "magenta", "grey40", "goldenrod"
)


# ============================================================
# [3] 공통 함수
# ============================================================

read_dat <- function(path) {
  lines <- readLines(path)

  header_idx <- which(str_starts(lines, "\\s*#"))[1]
  if (is.na(header_idx)) {
    stop(paste("헤더 줄(# frame rg)을 찾을 수 없습니다:", path))
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


parse_metadata <- function(filename, analysis_tag = "Rg") {
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
  setNames(rep(base_palette, length.out = length(levels_vec)), levels_vec)
}


add_structure_facet <- function(p, data) {
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
  pattern = "Rg\\.dat$",
  full.names = TRUE,
  ignore.case = TRUE
)

if (length(all_files) == 0) {
  stop(paste("Rg .dat 파일을 찾을 수 없습니다:", folder_path))
}

message(paste("▶ 발견된 Rg 파일:", length(all_files), "개"))
message(paste(" ", basename(all_files), collapse = "\n  "))


# ============================================================
# [5] 데이터 읽기 + metadata 결합
# ============================================================

rg_data <- map_dfr(all_files, function(f) {
  meta <- parse_metadata(f, "Rg")
  df <- read_dat(f) |> clean_names()

  df |> mutate(
    source = meta$source,
    file_date = meta$file_date,
    treatment = meta$treatment,
    subtype = meta$subtype,
    replicate = meta$replicate
  )
})

rg_candidates <- c("rg", "prot_rg", "radius_of_gyration", "gyration_radius")
rg_col <- rg_candidates[rg_candidates %in% names(rg_data)][1]

if (is.na(rg_col) || is.null(rg_col)) {
  stop(paste("Rg 컬럼을 찾을 수 없습니다. 현재 컬럼명:", paste(names(rg_data), collapse = ", ")))
}

rg_data <- rg_data |>
  rename(rg = all_of(rg_col)) |>
  mutate(
    frame = as.numeric(frame),
    rg = as.numeric(rg),
    time_ns = frame * time_per_frame,
    subtype_plot = if_else(is.na(subtype), "", subtype),
    variant_label = if_else(is.na(subtype), treatment, paste(treatment, subtype, sep = "_"))
  )

variant_levels <- unique(rg_data$variant_label)
variant_palette <- make_palette(variant_levels)

n_panels <- n_distinct(rg_data$variant_label)
facet_width <- max(6, facet_width_per_panel * n_panels)


# ============================================================
# [6] 출력 폴더
# ============================================================

out_dir <- file.path(path.expand(output_dir), target_folder)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)


# ============================================================
# [7] Plot 1: 패널 분리형 Rg
# ============================================================

plot_facet_base <- ggplot(rg_data, aes(x = time_ns, y = rg)) +
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
    title = paste("Protein Rg -", target_folder),
    x = "Time (ns)",
    y = expression(R[g]~"(" * ring(A) * ")")
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

plot_facet <- add_structure_facet(plot_facet_base, rg_data)

print(plot_facet)

ggsave(
  file.path(out_dir, paste0(target_folder, "_Rg_facet.png")),
  plot = plot_facet,
  width = facet_width,
  height = facet_height,
  dpi = 300,
  limitsize = FALSE
)


# ============================================================
# [8] Plot 2: 평균 비교형 Rg
# ============================================================

rg_mean <- rg_data |>
  group_by(variant_label, time_ns) |>
  summarise(rg_mean = mean(rg, na.rm = TRUE), .groups = "drop")

plot_mean <- ggplot(rg_mean, aes(x = time_ns, y = rg_mean, color = variant_label)) +
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
    title = paste("Protein Rg Mean -", target_folder),
    x = "Time (ns)",
    y = expression(R[g]~"(" * ring(A) * ")"),
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
  file.path(out_dir, paste0(target_folder, "_Rg_mean.png")),
  plot = plot_mean,
  width = mean_width,
  height = mean_height,
  dpi = 300
)

message(paste("✅ Rg 완료:", out_dir))
