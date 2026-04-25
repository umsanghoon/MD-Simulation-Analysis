# ============================================================
# H-bond 통합 분석 스크립트
# 작성: Hoon
#
# [목적]
#   md_simulation/Hbond/날짜폴더 안에 있는 Hbond .csv 파일들을 모두 읽어서
#   time-series 기반 H-bond figure들을 생성한다.
#
# [입력 파일명 규칙]
#   YYYY-MM-DD_STRUCTURE[_SUBTYPE]_rX_Hbond.csv
#
# 예:
#   2026-04-20_NPG6-4_r1_Hbond.csv
#   2026-04-20_NPG6-4_A3a_r1_Hbond.csv
#
# [입력 CSV 컬럼]
#   frame, all, intra_A, intra_B, intra_C, inter_AB, inter_AC, inter_BC
#
# [패널 표시]
#   subtype 없음: NPG6-4 한 줄 strip
#   subtype 있음: NPG6-4 / A3a 두 줄 strip
#
# [출력]
#   각 figure는 facet version과 mean version 두 개씩 저장됨.
#
#   Fig1: Total H-bonds over time
#   Fig3: Intra vs Inter H-bonds over time
#   Fig4: Inter-chain pair H-bonds over time
#   Fig5: Intra-chain H-bonds over time
#   Fig6: Inter-chain / Total H-bond ratio over time
#
# 총 10개 PNG 저장.
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

base_dir <- "~/Desktop/md_simulation/Hbond"
output_dir <- "~/Desktop/md_simulation/Hbond"

time_per_frame <- 0.1
x_max <- 100

save_excel <- FALSE

# ------------------------------------------------------------
# Figure별 y축 설정
# ------------------------------------------------------------

fig1_y_min <- -0.5
fig1_y_max <- 60
fig1_y_break_step <- 5

fig3_y_min <- -0.5
fig3_y_max <- 40
fig3_y_break_step <- 5

fig4_y_min <- -0.5
fig4_y_max <- 20
fig4_y_break_step <- 2.5

fig5_y_min <- -0.5
fig5_y_max <- 20
fig5_y_break_step <- 2.5

fig6_y_min <- 0
fig6_y_max <- 1
fig6_y_break_step <- 0.1

# ------------------------------------------------------------
# Figure 크기
# ------------------------------------------------------------

facet_height <- 5.5
facet_width_per_panel <- 3.8

mean_width <- 7.2
mean_height <- 6

# ------------------------------------------------------------
# 선 두께
# H-bond는 frame-to-frame fluctuation이 커서 RMSD/Rg보다 얇게 설정.
# ------------------------------------------------------------

line_alpha_replicate <- 0.16
line_width_replicate <- 0.20
line_width_mean <- 0.85

# ------------------------------------------------------------
# 색상
# ------------------------------------------------------------

base_palette <- c(
  "salmon", "steelblue", "forestgreen", "purple",
  "orange", "brown", "darkcyan", "magenta", "grey40", "goldenrod"
)

class_colors <- c(
  "Intra-chain" = "#00BFC4",
  "Inter-chain" = "#F8766D"
)

pair_colors <- c(
  "A-B" = "#E76F51",
  "A-C" = "#2A9D8F",
  "B-C" = "#457B9D"
)

intra_chain_colors <- c(
  "A" = "#7B2CBF",
  "B" = "#F77F00",
  "C" = "#2D6A4F"
)


# ============================================================
# [3] 공통 함수
# ============================================================

parse_metadata <- function(filename, analysis_tag = "Hbond") {
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


read_hbond_file <- function(path) {
  df <- read_csv(path, show_col_types = FALSE) |>
    clean_names()

  # 두 번째 줄에 Frame_no, Hbonds 같은 단위 row가 들어가는 경우 제거.
  df <- df |>
    filter(!str_detect(as.character(frame), regex("frame", ignore_case = TRUE))) |>
    mutate(
      across(
        c(frame, all, intra_a, intra_b, intra_c, inter_ab, inter_ac, inter_bc),
        as.numeric
      )
    )

  df
}


save_plot <- function(plot, filename, width, height) {
  ggsave(
    filename,
    plot = plot,
    width = width,
    height = height,
    dpi = 300,
    limitsize = FALSE
  )
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
  pattern = "Hbond\\.csv$",
  full.names = TRUE,
  ignore.case = TRUE
)

if (length(all_files) == 0) {
  stop(paste("Hbond .csv 파일을 찾을 수 없습니다:", folder_path))
}

message(paste("▶ 발견된 Hbond 파일:", length(all_files), "개"))
message(paste(" ", basename(all_files), collapse = "\n  "))


# ============================================================
# [5] 데이터 읽기 + metadata 결합
# ============================================================

hbond_data <- map_dfr(all_files, function(f) {
  meta <- parse_metadata(f, "Hbond")
  df <- read_hbond_file(f)

  df |> mutate(
    source = meta$source,
    file_date = meta$file_date,
    treatment = meta$treatment,
    subtype = meta$subtype,
    replicate = meta$replicate
  )
})

hbond_data <- hbond_data |>
  mutate(
    frame = as.numeric(frame),
    time_ns = frame * time_per_frame,
    intra_total = intra_a + intra_b + intra_c,
    inter_total = inter_ab + inter_ac + inter_bc,
    inter_ratio = inter_total / all,
    intra_ratio = intra_total / all,
    subtype_plot = if_else(is.na(subtype), "", subtype),
    variant_label = if_else(is.na(subtype), treatment, paste(treatment, subtype, sep = "_"))
  )

variant_levels <- unique(hbond_data$variant_label)
variant_palette <- make_palette(variant_levels)

n_panels <- n_distinct(hbond_data$variant_label)
facet_width <- max(6, facet_width_per_panel * n_panels)


# ============================================================
# [6] 출력 폴더
# ============================================================

out_dir <- file.path(path.expand(output_dir), target_folder)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)


# ============================================================
# [7] 공통 theme 함수
# ============================================================

theme_facet_common <- function() {
  theme_classic(base_size = 14) +
    theme(
      legend.position = "none",
      axis.line = element_line(color = "black", linewidth = 0.8),
      panel.border = element_rect(color = "black", fill = NA, linewidth = 0.8),
      strip.background = element_rect(color = "black", fill = "grey95", linewidth = 0.8),
      strip.text = element_text(face = "bold", hjust = 0.5, margin = margin(4, 4, 4, 4)),
      panel.spacing.x = unit(0.18, "lines")
    )
}


theme_mean_common <- function() {
  theme_classic(base_size = 14) +
    theme(
      aspect.ratio = 1,
      legend.position = "right",
      legend.title = element_blank(),
      axis.line = element_line(color = "black", linewidth = 0.8),
      panel.border = element_rect(color = "black", fill = NA, linewidth = 0.8)
    )
}


# ============================================================
# Figure 1: Total H-bonds over time
# ============================================================

fig1_base <- ggplot(hbond_data, aes(x = time_ns, y = all)) +
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
  scale_y_continuous(breaks = seq(0, fig1_y_max, by = fig1_y_break_step)) +
  coord_cartesian(xlim = c(0, x_max), ylim = c(fig1_y_min, fig1_y_max)) +
  labs(
    title = paste("Figure 1. Total H-bonds over Time -", target_folder),
    x = "Time (ns)",
    y = "Total H-bond count"
  ) +
  theme_facet_common()

fig1_facet <- add_structure_facet(fig1_base, hbond_data)
print(fig1_facet)

save_plot(
  fig1_facet,
  file.path(out_dir, paste0(target_folder, "_Fig1_total_Hbond_time_facet.png")),
  facet_width,
  facet_height
)

fig1_mean_data <- hbond_data |>
  group_by(variant_label, time_ns) |>
  summarise(value = mean(all, na.rm = TRUE), .groups = "drop")

fig1_mean <- ggplot(fig1_mean_data, aes(x = time_ns, y = value, color = variant_label)) +
  geom_line(linewidth = line_width_mean) +
  scale_color_manual(values = variant_palette, drop = FALSE) +
  scale_y_continuous(breaks = seq(0, fig1_y_max, by = fig1_y_break_step)) +
  coord_cartesian(xlim = c(0, x_max), ylim = c(fig1_y_min, fig1_y_max)) +
  labs(
    title = paste("Figure 1 Mean. Total H-bonds -", target_folder),
    x = "Time (ns)",
    y = "Total H-bond count",
    color = NULL
  ) +
  theme_mean_common()

print(fig1_mean)

save_plot(
  fig1_mean,
  file.path(out_dir, paste0(target_folder, "_Fig1_total_Hbond_time_mean.png")),
  mean_width,
  mean_height
)


# ============================================================
# Figure 3: Intra vs Inter H-bonds over time
# ============================================================

fig3_data <- hbond_data |>
  select(source, treatment, subtype, subtype_plot, variant_label, replicate, time_ns, intra_total, inter_total) |>
  pivot_longer(
    cols = c(intra_total, inter_total),
    names_to = "hbond_class",
    values_to = "hbond_count"
  ) |>
  mutate(
    hbond_class = recode(
      hbond_class,
      "intra_total" = "Intra-chain",
      "inter_total" = "Inter-chain"
    )
  )

fig3_base <- ggplot(fig3_data, aes(x = time_ns, y = hbond_count, color = hbond_class)) +
  geom_line(
    aes(group = interaction(source, hbond_class)),
    alpha = line_alpha_replicate,
    linewidth = line_width_replicate
  ) +
  stat_summary(
    aes(group = hbond_class),
    fun = mean,
    geom = "line",
    linewidth = line_width_mean
  ) +
  scale_color_manual(values = class_colors, drop = FALSE) +
  scale_y_continuous(breaks = seq(0, fig3_y_max, by = fig3_y_break_step)) +
  coord_cartesian(xlim = c(0, x_max), ylim = c(fig3_y_min, fig3_y_max)) +
  labs(
    title = paste("Figure 3. Intra vs Inter H-bonds over Time -", target_folder),
    x = "Time (ns)",
    y = "H-bond count",
    color = NULL
  ) +
  theme_facet_common() +
  theme(legend.position = "right")

fig3_facet <- add_structure_facet(fig3_base, fig3_data)
print(fig3_facet)

save_plot(
  fig3_facet,
  file.path(out_dir, paste0(target_folder, "_Fig3_intra_inter_Hbond_time_facet.png")),
  facet_width,
  facet_height
)

fig3_mean <- fig3_data |>
  group_by(variant_label, hbond_class, time_ns) |>
  summarise(value = mean(hbond_count, na.rm = TRUE), .groups = "drop") |>
  ggplot(aes(x = time_ns, y = value, color = hbond_class, linetype = variant_label)) +
  geom_line(linewidth = line_width_mean) +
  scale_color_manual(values = class_colors, drop = FALSE) +
  scale_y_continuous(breaks = seq(0, fig3_y_max, by = fig3_y_break_step)) +
  coord_cartesian(xlim = c(0, x_max), ylim = c(fig3_y_min, fig3_y_max)) +
  labs(
    title = paste("Figure 3 Mean. Intra vs Inter H-bonds -", target_folder),
    x = "Time (ns)",
    y = "H-bond count",
    color = NULL,
    linetype = "Structure"
  ) +
  theme_mean_common()

print(fig3_mean)

save_plot(
  fig3_mean,
  file.path(out_dir, paste0(target_folder, "_Fig3_intra_inter_Hbond_time_mean.png")),
  mean_width,
  mean_height
)


# ============================================================
# Figure 4: Inter-chain pair breakdown
# ============================================================

fig4_data <- hbond_data |>
  select(source, treatment, subtype, subtype_plot, variant_label, replicate, time_ns, inter_ab, inter_ac, inter_bc) |>
  pivot_longer(
    cols = c(inter_ab, inter_ac, inter_bc),
    names_to = "chain_pair",
    values_to = "hbond_count"
  ) |>
  mutate(
    chain_pair = recode(
      chain_pair,
      "inter_ab" = "A-B",
      "inter_ac" = "A-C",
      "inter_bc" = "B-C"
    )
  )

fig4_base <- ggplot(fig4_data, aes(x = time_ns, y = hbond_count, color = chain_pair)) +
  geom_line(
    aes(group = interaction(source, chain_pair)),
    alpha = line_alpha_replicate,
    linewidth = line_width_replicate
  ) +
  stat_summary(
    aes(group = chain_pair),
    fun = mean,
    geom = "line",
    linewidth = line_width_mean
  ) +
  scale_color_manual(values = pair_colors, drop = FALSE) +
  scale_y_continuous(breaks = seq(0, fig4_y_max, by = fig4_y_break_step)) +
  coord_cartesian(xlim = c(0, x_max), ylim = c(fig4_y_min, fig4_y_max)) +
  labs(
    title = paste("Figure 4. Inter-chain H-bond Breakdown over Time -", target_folder),
    x = "Time (ns)",
    y = "H-bond count",
    color = NULL
  ) +
  theme_facet_common() +
  theme(legend.position = "right")

fig4_facet <- add_structure_facet(fig4_base, fig4_data)
print(fig4_facet)

save_plot(
  fig4_facet,
  file.path(out_dir, paste0(target_folder, "_Fig4_inter_pair_Hbond_time_facet.png")),
  facet_width,
  facet_height
)

fig4_mean <- fig4_data |>
  group_by(variant_label, chain_pair, time_ns) |>
  summarise(value = mean(hbond_count, na.rm = TRUE), .groups = "drop") |>
  ggplot(aes(x = time_ns, y = value, color = chain_pair, linetype = variant_label)) +
  geom_line(linewidth = line_width_mean) +
  scale_color_manual(values = pair_colors, drop = FALSE) +
  scale_y_continuous(breaks = seq(0, fig4_y_max, by = fig4_y_break_step)) +
  coord_cartesian(xlim = c(0, x_max), ylim = c(fig4_y_min, fig4_y_max)) +
  labs(
    title = paste("Figure 4 Mean. Inter-chain H-bonds -", target_folder),
    x = "Time (ns)",
    y = "H-bond count",
    color = NULL,
    linetype = "Structure"
  ) +
  theme_mean_common()

print(fig4_mean)

save_plot(
  fig4_mean,
  file.path(out_dir, paste0(target_folder, "_Fig4_inter_pair_Hbond_time_mean.png")),
  mean_width,
  mean_height
)


# ============================================================
# Figure 5: Intra-chain breakdown
# ============================================================

fig5_data <- hbond_data |>
  select(source, treatment, subtype, subtype_plot, variant_label, replicate, time_ns, intra_a, intra_b, intra_c) |>
  pivot_longer(
    cols = c(intra_a, intra_b, intra_c),
    names_to = "chain",
    values_to = "hbond_count"
  ) |>
  mutate(
    chain = recode(
      chain,
      "intra_a" = "A",
      "intra_b" = "B",
      "intra_c" = "C"
    )
  )

fig5_base <- ggplot(fig5_data, aes(x = time_ns, y = hbond_count, color = chain)) +
  geom_line(
    aes(group = interaction(source, chain)),
    alpha = line_alpha_replicate,
    linewidth = line_width_replicate
  ) +
  stat_summary(
    aes(group = chain),
    fun = mean,
    geom = "line",
    linewidth = line_width_mean
  ) +
  scale_color_manual(values = intra_chain_colors, drop = FALSE) +
  scale_y_continuous(breaks = seq(0, fig5_y_max, by = fig5_y_break_step)) +
  coord_cartesian(xlim = c(0, x_max), ylim = c(fig5_y_min, fig5_y_max)) +
  labs(
    title = paste("Figure 5. Intra-chain H-bond Breakdown over Time -", target_folder),
    x = "Time (ns)",
    y = "H-bond count",
    color = NULL
  ) +
  theme_facet_common() +
  theme(legend.position = "right")

fig5_facet <- add_structure_facet(fig5_base, fig5_data)
print(fig5_facet)

save_plot(
  fig5_facet,
  file.path(out_dir, paste0(target_folder, "_Fig5_intra_chain_Hbond_time_facet.png")),
  facet_width,
  facet_height
)

fig5_mean <- fig5_data |>
  group_by(variant_label, chain, time_ns) |>
  summarise(value = mean(hbond_count, na.rm = TRUE), .groups = "drop") |>
  ggplot(aes(x = time_ns, y = value, color = chain, linetype = variant_label)) +
  geom_line(linewidth = line_width_mean) +
  scale_color_manual(values = intra_chain_colors, drop = FALSE) +
  scale_y_continuous(breaks = seq(0, fig5_y_max, by = fig5_y_break_step)) +
  coord_cartesian(xlim = c(0, x_max), ylim = c(fig5_y_min, fig5_y_max)) +
  labs(
    title = paste("Figure 5 Mean. Intra-chain H-bonds -", target_folder),
    x = "Time (ns)",
    y = "H-bond count",
    color = NULL,
    linetype = "Structure"
  ) +
  theme_mean_common()

print(fig5_mean)

save_plot(
  fig5_mean,
  file.path(out_dir, paste0(target_folder, "_Fig5_intra_chain_Hbond_time_mean.png")),
  mean_width,
  mean_height
)


# ============================================================
# Figure 6: Inter-chain / Total H-bond ratio
# ============================================================

fig6_base <- ggplot(hbond_data, aes(x = time_ns, y = inter_ratio)) +
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
  scale_y_continuous(breaks = seq(fig6_y_min, fig6_y_max, by = fig6_y_break_step)) +
  coord_cartesian(xlim = c(0, x_max), ylim = c(fig6_y_min, fig6_y_max)) +
  labs(
    title = paste("Figure 6. Inter-chain H-bond Ratio over Time -", target_folder),
    x = "Time (ns)",
    y = "Inter-chain H-bond / Total H-bond"
  ) +
  theme_facet_common()

fig6_facet <- add_structure_facet(fig6_base, hbond_data)
print(fig6_facet)

save_plot(
  fig6_facet,
  file.path(out_dir, paste0(target_folder, "_Fig6_inter_ratio_Hbond_time_facet.png")),
  facet_width,
  facet_height
)

fig6_mean_data <- hbond_data |>
  group_by(variant_label, time_ns) |>
  summarise(value = mean(inter_ratio, na.rm = TRUE), .groups = "drop")

fig6_mean <- ggplot(fig6_mean_data, aes(x = time_ns, y = value, color = variant_label)) +
  geom_line(linewidth = line_width_mean) +
  scale_color_manual(values = variant_palette, drop = FALSE) +
  scale_y_continuous(breaks = seq(fig6_y_min, fig6_y_max, by = fig6_y_break_step)) +
  coord_cartesian(xlim = c(0, x_max), ylim = c(fig6_y_min, fig6_y_max)) +
  labs(
    title = paste("Figure 6 Mean. Inter-chain H-bond Ratio -", target_folder),
    x = "Time (ns)",
    y = "Inter-chain H-bond / Total H-bond",
    color = NULL
  ) +
  theme_mean_common()

print(fig6_mean)

save_plot(
  fig6_mean,
  file.path(out_dir, paste0(target_folder, "_Fig6_inter_ratio_Hbond_time_mean.png")),
  mean_width,
  mean_height
)

message(paste("✅ Hbond 완료:", out_dir))
