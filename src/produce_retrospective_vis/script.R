palette <- c(
  Africa = "#d21d24",
  `North America` = "#5adf79",
  `South America` = "#016cf1",
  Asia = "#936500",
  Europe = "#5b4a7a",
  Oceania = "#982b1f"
)

indir <- dirname(covid_19_path)
indir <- glue::glue("{indir}/model_inputs")
infiles <- list.files(indir)

weeks <- gsub(
  pattern = "data_", replacement = "", infiles
) %>% gsub(x = ., pattern = ".rds", replacement = "")

infiles <- glue::glue("{indir}/{infiles}")
names(infiles) <- weeks

included <- purrr::map(infiles, readRDS)
included <- purrr::map_dfr(
  included, ~ data.frame(country = .$Country), .id = "week_starting"
)
## These are now included in the ECDC data. ECDC doesn;t distuish
## N and S America
## continents <- readr::read_csv(
##   "COVID-19-geographic-disbtribution-worldwide-2020-06-14.csv"
## ) %>%
##   dplyr::select(`Countries and territories`, popData2018, continent) %>%
## dplyr::distinct() %>%
## janitor::clean_names()

continents <- readr::read_csv(
  "country-and-continent-codes-list.csv"
)
continents <- janitor::clean_names(continents)
## Some are dups, not that it matters..
dups <- duplicated(continents$three_letter_country_code)
continents <- continents[!dups, ]
continents <- continents[, c(
  "continent_name",
  "three_letter_country_code"
)]

included$iso3c <- countrycode::countrycode(
  snakecase::to_title_case(included$country), "country.name", "iso3c"
)
included$country[included$country == "Czech_Republic"] <- "Czechia"

included <- dplyr::left_join(
  included, continents, by = c("iso3c" = "three_letter_country_code")
)

## color scheme from Gapminder
## gapminder::continent_colors
pbar <- ggplot(included, aes(week_starting)) +
  geom_bar(position = "dodge", aes(fill = continent_name)) +
  theme_classic() +
  theme(legend.position = "top", legend.title = element_blank()) +
  scale_fill_manual(values = palette) +
  ylab("Countries with active transmission") +
  xlab("Week Starting")



x <- dplyr::count(included, week_starting, continent_name)
x$week_starting <- as.Date(x$week_starting)

y <- dplyr::filter(x, week_starting == "2020-06-21")
labels <- data.frame(
  x = as.Date("2020-06-24"),
  label = c("Asia", "Europe", "North America", "South America", "Africa")
)

labels <- dplyr::left_join(labels, y, by = c("label" = "continent_name"))

pline <- ggplot() +
  geom_line(data = x, aes(week_starting, n, col = continent_name), size = 1.5) +
  ## geom_text_repel(
  ##   data = labels,
  ##   aes(x = x, y = n, label = label, col = label)
  ## ) +
  scale_x_date(
    breaks = seq(
      from = as.Date("2020-03-01"),
      to = as.Date("2020-06-27"),
      by = "2 weeks"
    ),
    limits = c(as.Date("2020-03-01"), as.Date("2020-06-27"))
  ) +
  coord_cartesian(clip = 'off') +
  theme_classic() +
  theme(legend.position = "none", legend.title = element_blank()) +
  scale_color_manual(values = palette) +
  ylab("Countries with active transmission") +
  xlab("Week Starting")

ggsave("n_included_bar.png", pbar)
ggsave("n_included_line.png", pline)

#####################################################################
#####################################################################
############# Epicurve by continent #################################
#####################################################################
#####################################################################

model_input <- readRDS("model_input.rds")
model_input <- tidyr::gather(model_input, country, deaths, -dates)
model_input <- model_input[model_input$country %in% included$country, ]
model_input$iso3c <- countrycode::countrycode(
  snakecase::to_title_case(model_input$country), "country.name", "iso3c"
)

model_input <- dplyr::left_join(
  model_input, continents, by = c("iso3c" = "three_letter_country_code")
)

by_continent <- dplyr::group_by(model_input, dates, continent_name) %>%
  dplyr::summarise(deaths = sum(deaths)) %>%
  dplyr::ungroup()


epicurve <- ggplot() +
  geom_line(
    data = by_continent,
    aes(dates, deaths, col = continent_name),
    size = 1.2
  ) +
  scale_color_manual(values = palette) +
  scale_x_date(
    breaks = seq(
      from = as.Date("2020-03-01"),
      to = as.Date("2020-06-27"),
      by = "2 weeks"
    ),
    limits = c(as.Date("2020-03-01"), as.Date("2020-06-27"))
  ) +
  theme_classic() +
  theme(legend.position = "top", legend.title = element_blank()) +
  xlab("") +
  ylab("Deaths")

y <- dplyr::filter(by_continent, dates == max(dates))
y$deaths <- y$deaths + 1
labels <- data.frame(
  x = max(model_input$dates) + 5,
  label = c("Asia", "Europe", "North America", "South America", "Africa")
)

## labels <- dplyr::left_join(labels, y, by = c("label" = "continent_name"))
## epicurve <- epicurve +
##   geom_text_repel(
##     data = labels, aes(x = x, y = deaths, label = label, col = label)
##   ) + coord_cartesian(clip = "off")

ggsave("epicurve_by_continent.png", epicurve)


## Side by side:
p <- cowplot::plot_grid(epicurve, pline, nrow = 2, labels = "AUTO", align = "hv")
ggsave("epicurve_pline.png", p)
#####################################################################
#####################################################################
############# Rt by population ######################################
#####################################################################
#####################################################################
unweighted_rt_qntls <- readRDS("unweighted_rt_qntls.rds") %>%
  dplyr::filter(si == "si_2")

ecdc <- readr::read_csv(
  "COVID-19-geographic-disbtribution-worldwide-2020-06-14.csv"
  ) %>%
  dplyr::select(
    country = `Countries and territories`, popData2018, continent
  ) %>% dplyr::distinct()

unweighted_rt_qntls$country[unweighted_rt_qntls$country == "Czech_Republic"] <- "Czechia"
unweighted_rt_qntls <- dplyr::left_join(unweighted_rt_qntls, ecdc)

x <- dplyr::group_by(unweighted_rt_qntls, forecast_date, phase) %>%
  dplyr::summarise(total_pop = sum(popData2018)) %>%
  dplyr::ungroup()

x$forecast_date <- as.Date(x$forecast_date)

phase_palette <- c(
  decline = "018571",
  growing = "#a6611a",
  unclear = "#dfc27d",
  `stable/growing slowly` = "#80cdc1"
)

p <- ggplot() +
  geom_line(
    data = x, aes(forecast_date, total_pop, col = phase), size = 1.2
  ) +
  scale_color_manual(
    values = phase_palette
  ) +
  theme_classic() +
  theme(legend.position = "top", legend.title = element_blank()) +
  xlab("") +
  ylab("Population") +
  scale_x_date(
    date_breaks = "2 weeks",
    limits = c(as.Date("2020-03-01"), NA)
  )


ggsave("population_by_phase.png", p)