#' Calculate all the pressures score for each (sub)goal.
#'
#' @param layers object \code{\link{Layers}}
#' @param conf object \code{\link{Conf}}
#' @return data.frame containing columns 'region_id' and per subgoal pressures score
#' @import dplyr
#' @import tidyr
#' @export
CalculatePressuresAll <- function(layers, conf) {

  ### reporting 1
  cat(sprintf('Calculating Pressures for each region...\n'))

  ### get pressure matrix, goal elements, weights, categories, layers
  p_matrix <- conf$pressures_matrix
  p_matrix <- tidyr::gather(p_matrix, layer, m_intensity,
                            -c(goal, element, element_name)) %>%    ### format the pressure matrix so it is a dataframe
    dplyr::filter(!is.na(m_intensity)) %>%
    dplyr::select(goal, element, layer, m_intensity)

  ### p_elements: make into a data.frame
  p_element <- conf$config$pressures_element
  if (length(p_element) >= 1) { ### only if there are any goals that have elements
    p_element <- plyr::ldply(p_element)
    names(p_element) <- c('goal', 'layer')
  }

  ### gamma weighting for social vs. ecological pressure categories
  p_gamma <- conf$config$pressures_gamma

  ### table describing pressure categories and subcategories
  p_categories <- unique(conf$pressure_categories)

  ### reporting 2
  cat(sprintf('There are %s pressures subcategories: %s \n',
              length(unique(p_categories$subcategory)),
                     paste(unique(p_categories$subcategory), collapse = ', ')))

  ### error if the config.R weighting files are not actually included in the the data
  if ( !is.null(p_element) ) {
    obs_data <- SelectLayersData(layers, layers = p_element$layer) %>%
      .$layer %>%
      unique()
    exp_data <- unique(p_element$layer)
    dif <- setdiff(exp_data, obs_data)
    if (length(dif) > 0) {
      stop(sprintf('weighting data layers identified in config.r do not exist; please update layers.csv and layers folder to include: %s',
                   paste(dif, collapse = ', ')))
    }
  }

  ### error if pressure categories deviate from "ecological" and "social"
  check <- setdiff(c("ecological", "social"), unique(p_categories$category))
  if (length(check) > 0){
    stop(sprintf('In pressures_categories.csv, the "category" variable does not include %s',
                 paste(check, collapse = ', ')))
  }

  check <- setdiff(unique(p_categories$category), c("ecological", "social"))
   if (length(check) > 0) {
    stop(sprintf('In pressures_categories.csv, the "category" variable includes %s',
                 paste(check, collapse = ', ')))
  }


  ### list of pressure layers from the pressures_matrix
  p_layers <- sort(names(conf$pressures_matrix)[!names(conf$pressures_matrix) %in%
                                                 c('goal', 'element', 'element_name')])


  ### error if layer value range is incorrect
  if (!all(subset(layers$meta, layer %in% p_layers, val_0to1, drop = TRUE))){
    stop(sprintf('These pressures layers must range in value from 0 to 1:\n%s',
                 paste(
                   unlist(
                     layers$meta %>%
                       dplyr::filter(layer %in% p_layers & val_0to1 == F) %>%
                       dplyr::select(layer)),
                   collapse = ', ')))
  }

  ### error if matrix multipliers are not between 0 and 3
  # if(sum(p_matrix$value > 3 | p_matrix$value < 1) > 0) {
  if(sum(!p_matrix$m_intensity %in% c(1:3) ) > 0) {
    message(sprintf('There are values in pressures_matrix.csv that are > 3 or < 1'))
  }


  ### error check: that matrix and categories table include the same pressure layers
  check <- setdiff(p_layers, p_categories$layer)
  if (length(check) >= 1) {
    message(sprintf('These pressure layers are in the pressure_matrix.csv but not in pressure_categories.csv:\n%s',
                    paste(check, collapse = ', ')))
  }

  check <- setdiff(p_categories$layer, p_layers)
  if (length(check) >= 1) {
    message(sprintf('These pressure layers are in the pressure_categories.csv but not in the pressure_matrix.csv:\n%s',
                    paste(check, collapse = ', ')))
  }

  check <- setdiff(p_layers, names(layers))
  if (length(check) >= 1) {
    message(sprintf('These pressure layers are in the pressure_matrix.csv but not in the layers environment:\n%s',
                    paste(check, collapse = ', ')))
  }


  ### setup initial data.frame for column binding results by region
  regions_dataframe <- SelectLayersData(layers,
                                                 layers = conf$config$layer_region_labels,
                                                 narrow = TRUE) %>%
    dplyr::select(region_id = id_num)
  regions_vector <- regions_dataframe[['region_id']]


  ### create the weighting scheme
  eco_soc_weight <- data.frame(category = c("ecological", "social"),
                               weight   = c(p_gamma, 1 - p_gamma),
                               stringsAsFactors = FALSE)


  ### ID relevant data year for each layer (if there is no year data, the year is assigned as 20100)
  if(nrow(conf$scenario_data_years) > 0) {

    scenario_data_year <- conf$scenario_data_years %>%
      dplyr::filter(layer_name %in% p_layers)

    scenario_data_year <- scenario_data_year[scenario_data_year$scenario_year == layers$data$scenario_year, ] %>%
      dplyr::select(layer_name, scenario_year, data_year)

    layers_no_years <- setdiff(p_layers, scenario_data_year$layer_name)
    
    #if there are layers that do not have years, then we add them in through this layers_no_years_df year year 20100
    if(length(layers_no_years) > 0){
      
    layers_no_years_df <- data.frame(layer_name    = layers_no_years,
                                     scenario_year = 20100,  ### creating a fake variable to match up here
                                     data_year     = 20100,
                                     stringsAsFactors = FALSE)

    scenario_data_year <- rbind(scenario_data_year, layers_no_years_df)
    }
    
    scenario_data_year <- scenario_data_year %>%
      dplyr::select(layer = layer_name, year = data_year)

  } else{
    scenario_data_year <- data.frame(layer = p_layers,
                                     year  = 20100,
                                     stringsAsFactors = FALSE)
  }



  ### get each pressure data layer and select the appropriate year of data:
  p_rgn_layers_data <- SelectLayersData(layers, layers = p_layers)

  if(length(which(names(p_rgn_layers_data) == "year")) == 0){
    p_rgn_layers_data$year <- NA
  }


  p_rgn_layers_data <- p_rgn_layers_data  %>%
    dplyr::filter(id_num %in% regions_vector) %>%
    dplyr::select(region_id = id_num,
                  year,
                  val_num,
                  layer) %>%
    dplyr::filter(!is.na(val_num)) %>%
    dplyr::mutate(year = ifelse(is.na(year), 20100, year))

  p_rgn_layers <- scenario_data_year %>%
    dplyr::left_join(p_rgn_layers_data, by=c("year", "layer")) %>%
    select(region_id, val_num, layer)

  ### error check: matrix and region data layers include the same pressure factors
  check <- setdiff(p_layers, p_rgn_layers$layer)
  if (length(check) >= 1) {
    message(sprintf('These pressure layers are in the pressures_matrix.csv, but there are no associated data layers:\n%s',
                    paste(check, collapse = ', ')))
  }

  check <- setdiff(p_rgn_layers$layer, p_layers)
  if (length(check) >= 1) {
    message(sprintf('These pressure layers have data layers, but are not included in the pressures_matrix.csv:\n%s',
                    paste(check, collapse = ', ')))
  }


  ### further preparation of matrix data for analysis
  p_matrix <- p_matrix %>%
    dplyr::left_join(p_categories, by="layer") %>%
    dplyr::group_by(goal, element, category, subcategory) %>%
    dplyr::mutate(max_subcategory = max(m_intensity)) %>%
    data.frame()

  ### merge the region data layers and the pressure matrix
  rgn_matrix <- dplyr::left_join(p_matrix, p_rgn_layers, by="layer")


  ### summarize cumulative pressure for each subcategory
  ### (first find maximum pressure in each pressure subcategory)
  calc_pressure <- rgn_matrix %>%
    dplyr::mutate(pressure_intensity = m_intensity * val_num) %>%
    data.frame()


  ### separate method for ecological pressures
  calc_pressure_eco <- calc_pressure %>%
    dplyr::filter(category == "ecological") %>%
    dplyr::group_by(goal, element, category, subcategory, max_subcategory, region_id) %>%
    dplyr::summarize(cum_pressure = sum(pressure_intensity, na.rm = TRUE) / 3) %>%
    dplyr::mutate(cum_pressure = ifelse(cum_pressure > 1, 1, cum_pressure)) %>%
    dplyr::ungroup() %>%
    data.frame()

  ### separate method for social pressures
  calc_pressure_soc <- calc_pressure %>%
    dplyr::filter(category == "social") %>%
    dplyr::group_by(goal, element, category, subcategory, max_subcategory, region_id) %>%
    dplyr::summarize(cum_pressure = mean(pressure_intensity)) %>%
    dplyr::mutate(cum_pressure = ifelse(cum_pressure > 1, 1, cum_pressure)) %>%
    dplyr::ungroup() %>%
    data.frame()

  ### combine social and ecological
  calc_pressure <- rbind(calc_pressure_eco, calc_pressure_soc)

  ### average of the pressure subcategories (weighted by highest intensity for each region/subcategory)
  calc_pressure <- calc_pressure %>%
    dplyr::group_by(goal, element, category, region_id) %>%
    dplyr::summarize(pressure = weighted.mean(cum_pressure, max_subcategory)) %>%
    dplyr::ungroup() %>%
    data.frame()

  ### combine ecological and social pressures, based on gamma
  calc_pressure <- calc_pressure %>%
    dplyr::left_join(eco_soc_weight, by="category") %>%
    dplyr::group_by(goal, element, region_id) %>%
    dplyr::summarize(pressure = weighted.mean(pressure, weight)) %>%
    dplyr::ungroup() %>%
    data.frame()


  ### Deal with goals with goal elements
  if (length(p_element) >= 1) { ### only if there are any goals that have elements
    p_element_layers <- SelectLayersData(layers, layers = p_element$layer) %>%
      dplyr::filter(id_num %in% regions_vector) %>%
      dplyr::select(region_id  = id_num,
                    element    = category,
                    element_wt = val_num,
                    layer) %>%
      dplyr::filter(!is.na(element)) %>%
      dplyr::filter(!is.na(element_wt)) %>%
      dplyr::left_join(p_element, by="layer") %>%
      dplyr::select(region_id, goal, element, element_wt) %>%
      dplyr::mutate(element = as.character(element))

    ### data check:  Make sure elements of each goal are included in the pressure_matrix.R
    check <- setdiff(paste(p_element_layers$goal,
                           p_element_layers$element,
                           sep = "-"),
                     paste(p_matrix$goal[p_matrix$goal %in% p_element$goal],
                           p_matrix$element[p_matrix$goal %in% p_element$goal],
                           sep = "-"))
    if (length(check) >= 1) {
      message(sprintf('These goal-elements are in the weighting data layers, but not included in the pressure_matrix.csv:\n%s',
                      paste(check, collapse = ', ')))
    }

    check <- setdiff(paste(p_matrix$goal[p_matrix$goal %in% p_element$goal],
                           p_matrix$element[p_matrix$goal %in% p_element$goal],
                           sep = "-"),
                     paste(p_element_layers$goal,
                           p_element_layers$element,
                           sep = "-"))
    if (length(check) >= 1) {
      message(sprintf('These goal-elements are in the pressure_matrix.csv, but not included in the weighting data layers:\n%s',
                      paste(check, collapse = ', ')))
    }

    ### Reset calc_pressure as a weighted average of the elements:
    calc_pressure <- calc_pressure %>%
      dplyr::left_join(p_element_layers, by = c('region_id', 'goal', 'element')) %>%
      dplyr::filter(!(is.na(element_wt) & goal %in% p_element$goal))  %>%
      dplyr::mutate(element_wt = ifelse(is.na(element_wt), 1, element_wt)) %>%
      dplyr::group_by(goal, region_id) %>%
      dplyr::summarize(pressure = weighted.mean(pressure, element_wt)) %>% ### retain a 'pressure' column
      dplyr::ungroup() %>%
      data.frame()

  } ### end if(length(p_element) >= 1) for goals with elements

  ### return scores
  scores <- regions_dataframe %>%
    dplyr::left_join(calc_pressure, by = "region_id") %>%
    dplyr::mutate(dimension = "pressures") %>%
    dplyr::select(goal, dimension, region_id, score = pressure) %>%
    dplyr::mutate(score = round(score * 100, 2))

  return(scores)

}
