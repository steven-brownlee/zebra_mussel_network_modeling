
# Load zm buffer

qgis_bbox <- read_sf('processed/qgis_bbox.gpkg')

```{r}

zm_buffer_collected <- read_sf('data_directory/processed/zm_buffer.gpkg')

```


```{r}

qgis_bbox_transformed <- qgis_bbox %>% st_transform(crs = 5070)

overlay_grid <- st_make_grid(qgis_bbox_transformed, cellsize = 2000, what = 'polygons',
                             square = FALSE) %>% st_as_sf() %>% st_transform(crs = 4326)

write_sf(overlay_grid, 'data_directory/processed/2km_hexagon_grid.gpkg')

```

```{r}

overlay_grid <- read_sf('data_directory/processed/2km_hexagon_grid.gpkg')

overlay_selection <- qgis_run_algorithm(
  "native:extractbylocation",
  INPUT = 'data_directory/2km_hexagon_grid.gpkg',
  PREDICATE = 6,
  INTERSECT = 'data_directory/cec_coastline.gpkg',
  OUTPUT = 'data_directory/2km_hexagon_selection.gpkg'
)

overlay_selection <- read_sf('data_directory/processed/2km_hexagon_selection.gpkg')

write_sf(overlay_selection, 'data_directory/processed/2km_hexagon_selection.gpkg', driver = 'GPKG')

```

# Read hexagon grid


```{r}

overlay_selection <- read_sf('data_directory/processed/2km_hexagon_selection.gpkg') %>% 
  rowid_to_column('uid') 

overlay_centroids <- st_centroid(overlay_selection) %>% mutate(lon = sf::st_coordinates(.)[,1],
                                                               lat = sf::st_coordinates(.)[,2])

overlay_centroids_joined <- st_join(overlay_centroids, overlay_selection)

write_sf(overlay_centroids_joined, 'data_directory/processed/2km_centroids_joined.gpkg')

overlay_centroids <- overlay_centroids_joined %>% select(uid.y, lon, lat) %>% rename(uid = uid.y) %>% 
  st_drop_geometry()

write_rds(overlay_centroids, 'data_directory/processed/2km_centroids_table.rds')

```

# Extract data from OpenStreetMap

```{r}

overlay_centroids <- readRDS('data_directory/processed/2km_centroids_table.rds')

```
# d

# New workflow

```{r}

na_data <- read_sf('data_directory/na_highway_filtered_final.gpkg')

na_data <- na_data %>% select(-waterway, -aerialway, -barrier, -man_made, -z_order) 

na_data <- st_centroid(na_data)

na_data <- st_join(na_data, hexagon_dissolved)

write_sf(na_data, 'data_directory/na_highway_grouped.gpkg')

```



```{r}

na_data <- read_sf('data_directory/na_highway_filtered_final.gpkg') %>% 
  select(-waterway, -aerialway, -barrier, -man_made, -z_order) %>% rowid_to_column()

###

divided_dataset <- tibble(x = seq(1:18135029))

num_groups = 2000

divided_dataset <- divided_dataset %>% mutate(grouping = (row_number()-1) %/% (n()/num_groups)) %>% 
  group_by(grouping) %>% 
  summarize(min_x = min(x), max_x = max(x)) %>% select(-grouping)


sequence_start = pull(divided_dataset, min_x)

sequence_end = pull(divided_dataset, max_x)

for (i in 1:2000)  {
  group_slice <- na_data %>% 
    filter(rowid >= sequence_start[i] & rowid < sequence_end[i]) %>% 
    st_transform(crs = 'ESRI:102008')
  write_sf(group_slice, paste0('scratch/group_slice/group_slice_', i, '.gpkg'))
  print(paste('Completed:', i))
}

```

```{r}

osm_slice_list = list.files('/home/steven/Documents/common/thesis/ch2/gis_data/scratch/group_slice/', 
                            pattern = 'group_slice_*',
                            full.names = TRUE,
                            recursive = TRUE)

linesplit_small <- function(id, osm_file) {
  osm_filtered <- osm_file %>% filter(osm_id == id) 
  osm_interior_length <- osm_filtered$length
  osm_interpolated <- osm_filtered %>% st_as_sfc %>% 
    st_line_interpolate(dist = seq(0, osm_interior_length, osm_interior_length/2)) %>% st_as_sf() %>% 
    mutate(osm_id = as.character(id)) %>% mutate(lon = sf::st_coordinates(.)[,1],
                                                 lat = sf::st_coordinates(.)[,2]) %>% st_drop_geometry()
  osm_aspatial <- osm_filtered %>% st_drop_geometry()
  osm_joined <- left_join(osm_interpolated, osm_filtered, by = 'osm_id')
  return(osm_joined)
}

linesplit_regular <- function(id, osm_file, maxlength) {
  osm_filtered <- osm_file %>% filter(osm_id == id) 
  osm_interior_length <- osm_filtered$length
  osm_interpolated <- osm_filtered %>% st_as_sfc %>% 
    st_line_interpolate(dist = seq(0, osm_interior_length, maxlength)) %>% st_as_sf() %>% 
    mutate(osm_id = as.character(id)) %>% mutate(lon = sf::st_coordinates(.)[,1],
                                                 lat = sf::st_coordinates(.)[,2]) %>% st_drop_geometry()
  osm_aspatial <- osm_filtered %>% st_drop_geometry()
  osm_joined <- left_join(osm_interpolated, osm_filtered, by = 'osm_id')
  return(osm_joined)
}


outer_process <- function(osm_slice) {
  
  osm_interior <- read_sf(osm_slice)
  #
  osm_interior <- osm_interior %>% mutate(length = as.numeric(st_length(geom)))
  osm_less_1km <- osm_interior %>% filter(length < 1000)
  osm_greater_1km <- osm_interior %>% filter(length > 1000)
  #
  less_1km_ids <- unique(osm_less_1km$osm_id)
  greater_1km_ids <- unique(osm_greater_1km$osm_id)
  #
  p  <- progressr::progressor(along = less_1km_ids)
  less_1km_result <- future_map(less_1km_ids, 
                                globals = c(osm_interior = osm_interior),
                                ~{ p()
                                  linesplit_small(.x, osm_file = osm_interior)})
  p  <- progressr::progressor(along = greater_1km_ids)
  greater_1km_result <- future_map(greater_1km_ids, 
                                   globals = c(osm_interior = osm_interior),
                                   ~{ p()
                                     linesplit_regular(.x, osm_file = osm_interior, maxlength = 500)})
  less_1km_result <- bind_rows(less_1km_result)
  greater_1km_result <- bind_rows(greater_1km_result)
  final_results <- bind_rows(less_1km_result, greater_1km_result)
  return(final_results)
}


plan(callr, workers = 6)


for (i in 1:710) {
  with_progress({osm_processed <- outer_process(osm_slice_list[i])})
  osm_processed <- bind_rows(osm_processed)
  print(paste('Completed:', i))
  write_csv(osm_processed, paste0('scratch/point_outdir/osm_point_table_processed_', i ,'.csv'))
}

for (i in 711:1420) {
  with_progress({osm_processed <- outer_process(osm_slice_list[i])})
  osm_processed <- bind_rows(osm_processed)
  print(paste('Completed:', i))
  write_csv(osm_processed, paste0('scratch/point_outdir/osm_point_table_processed_', i ,'.csv'))
  gc()
}

for (i in 1420:2000) {
  with_progress({osm_processed <- outer_process(osm_slice_list[i])})    
  osm_processed <- bind_rows(osm_processed)
  print(paste('Completed:', i))
  write_csv(osm_processed, paste0('scratch/point_outdir/osm_point_table_processed_', i ,'.csv'))
}

hexagon_dissolved <- read_sf('data_directory/2km_hexagon_dissolved.gpkg')

osm_data_list = list.files('scratch/point_outdir/', 
                           pattern = 'osm_point_table_processed_*',
                           full.names = TRUE,
                           recursive = TRUE)


for (i in 1:length(osm_data_list))  {
  osm_point_intermediate <- read_csv(osm_data_list[i], show_col_types = FALSE)
  osm_point_intermediate <- st_as_sf(osm_point_intermediate, 
                                     coords = c('lon', 'lat'), 
                                     crs = st_crs('ESRI:102008')) %>% 
    st_transform(crs = 4326)
  osm_point_intermediate <- st_join(osm_point_intermediate, hexagon_dissolved) 
  osm_point_intermediate <- osm_point_intermediate %>% 
    mutate(lon = sf::st_coordinates(.)[,1],
           lat = sf::st_coordinates(.)[,2]) %>% 
    st_drop_geometry()
  write_csv(osm_point_intermediate, paste0('scratch/point_outdir/osm_points_organized_', i, '.csv'))
  print(paste('Written:', i))
}


```


```{r}

osm_data_list = list.files('scratch/point_outdir/', 
                           pattern = 'osm_points_organized_*',
                           full.names = TRUE,
                           recursive = TRUE)

osm_local_filter <- function(sub_tibble) {
  if (all(is.na(sub_tibble$lanes))) {
    sub_tibble$lanes <- sub_tibble$lanes
  } else {
    max_lane_val <- max(sub_tibble$lanes, na.rm = TRUE)
    sub_tibble$lanes <- replace_na(sub_tibble$lanes, max_lane_val)
  }
  if (all(is.na(sub_tibble$max_speed))) {
    sub_tibble$max_speed <- sub_tibble$max_speed
  } else {
    max_max_speed <- max(sub_tibble$max_speed, na.rm = TRUE)
    sub_tibble$max_speed <- replace_na(sub_tibble$max_speed, max_max_speed)
  }
  return(sub_tibble)
}


osm_filter <- function(input_table) {
  input_table <- read_csv(input_table, show_col_types = FALSE)
  combined_osm_table <- input_table %>% 
    rowid_to_column('point_id')
  combined_osm_table$name <- sub('^$', 'no_name', combined_osm_table$name)
  
  osm_table_ids <- combined_osm_table %>% select(point_id, osm_id, group_id, name, lon, lat)
  
  osm_table_lanes <- combined_osm_table %>% filter(grepl('lanes', other_tags)) %>% 
    separate_longer_delim(other_tags, delim = ',') %>%  
    filter(grepl('"lanes"=>', other_tags)) %>%  
    mutate(across('other_tags', str_replace, '"lanes"=>', '')) %>% 
    mutate(across('other_tags', str_replace, '"', '')) %>% 
    mutate(across('other_tags', str_replace, '"', '')) %>% 
    rename(lanes = other_tags) %>% select(point_id, osm_id, name, lanes) %>% 
    st_drop_geometry()
  
  
  osm_table_lanes <- osm_table_lanes
  
  osm_table_lanes$lanes <- sub("\\;.*", "", osm_table_lanes$lanes)
  
  osm_table_lanes$lanes <- gsub("[^0-9]", NA, osm_table_lanes$lanes)
  
  osm_table_lanes <- osm_table_lanes %>% drop_na()
  
  osm_table_lanes$lanes <- as.numeric(osm_table_lanes$lanes)
  
  ####
  
  osm_table_maxspeed <- combined_osm_table %>% filter(grepl('maxspeed', other_tags)) %>% 
    separate_longer_delim(other_tags, delim = ',')  %>% 
    filter(grepl('"maxspeed"=>', other_tags)) %>% 
    mutate(across('other_tags', str_replace, '"maxspeed"=>', ''))%>% 
    rename(max_speed = other_tags)  %>% 
    filter(!grepl('unposted', max_speed)) %>% 
    filter(!grepl('slow', max_speed)) %>% 
    filter(!grepl('implicit', max_speed)) %>% 
    filter(!grepl('default', max_speed)) %>% 
    filter(!grepl('signals', max_speed)) %>% 
    filter(!grepl('Variable', max_speed)) %>% 
    select(point_id, osm_id, max_speed)
  
  osm_table_maxspeed_kmh <- osm_table_maxspeed %>% 
    filter(!grepl('mph', max_speed) & !grepl('MPH', max_speed)) %>% 
    mutate(across('max_speed', str_replace, '"', '')) %>% 
    mutate(across('max_speed', str_replace, '"', ''))
  
  osm_table_maxspeed_kmh$max_speed <- sub("\\;.*", "", osm_table_maxspeed_kmh$max_speed)
  
  osm_table_maxspeed_kmh$max_speed <- gsub("[^0-9.-]", NA, osm_table_maxspeed_kmh$max_speed) 
  
  osm_table_maxspeed_kmh$max_speed <- as.numeric(osm_table_maxspeed_kmh$max_speed)
  
  osm_table_maxspeed_kmh <- osm_table_maxspeed_kmh %>% drop_na()
  
  ###
  
  osm_table_maxspeed_mph <- osm_table_maxspeed %>% filter(grepl('mph', max_speed)) %>% 
    mutate(across('max_speed', str_replace, ' mph', '')) %>%
    mutate(across('max_speed', str_replace, 'mph', ''))
  
  osm_table_maxspeed_mph$max_speed <- sub("\\;.*", "", osm_table_maxspeed_mph$max_speed)
  
  osm_table_maxspeed_mph <- osm_table_maxspeed_mph %>% 
    mutate(across('max_speed', str_replace, '"', '')) %>% 
    mutate(across('max_speed', str_replace, '"', '')) 
  
  osm_table_maxspeed_mph$max_speed <- as.numeric(osm_table_maxspeed_mph$max_speed)
  
  osm_table_maxspeed_mph <- osm_table_maxspeed_mph %>% drop_na()
  
  osm_table_maxspeed_mph <- osm_table_maxspeed_mph %>% 
    mutate(max_speed_kmh = max_speed*1.609344) %>% 
    select(point_id, osm_id, max_speed_kmh) %>% 
    rename(max_speed = max_speed_kmh)
  
  osm_table_maxspeed_combined <- rbind(osm_table_maxspeed_mph, osm_table_maxspeed_kmh)
  
  osm_table_maxspeed_combined <- osm_table_maxspeed_combined %>% 
    filter(max_speed < 120)
  
  ###
  
  osm_table_type <- combined_osm_table %>% select(point_id, osm_id, highway) %>% rename(type = highway)
  
  osm_table_type$type <- factor(osm_table_type$type, 
                                levels = c('residential', 'unclassified', 
                                           'tertiary', 'secondary', 
                                           'primary', 'trunk', 'motorway'))
  
  osm_filtered_data <- left_join(osm_table_ids, osm_table_type, 
                                 by = 'point_id',
                                 relationship = 'one-to-one',
                                 keep = FALSE)
  
  osm_filtered_data <- left_join(osm_filtered_data, osm_table_lanes, 
                                 by = 'point_id',
                                 relationship = 'one-to-one')
  
  osm_filtered_data <- left_join(osm_filtered_data, osm_table_maxspeed_combined, 
                                 by = 'point_id',
                                 relationship = 'one-to-one')
  osm_filtered_data <- osm_filtered_data %>% select(lon, lat, point_id, osm_id.x, group_id, 
                                                    name.x, type, lanes, max_speed) %>% 
    rename(osm_id = osm_id.x, name = name.x)
  
  osm_filtered_data_list <- osm_filtered_data %>% group_split(name)
  
  osm_filtered_data_vector <- map(osm_filtered_data_list, osm_local_filter)
  
  osm_filtered_data <- bind_rows(osm_filtered_data_vector)
  
  return(osm_filtered_data)
  
}

for (i in 1:2000) {
  osm_processed <- osm_filter(osm_data_list[i])
  write_csv(osm_processed, paste0('scratch/filtered_outdir/osm_filtered_data_', i, '.csv'))
  print(paste('Completed:', i))
}

osm_data_list = list.files('scratch/', 
                           pattern = 'osm_filtered_data_*',
                           full.names = TRUE,
                           recursive = TRUE)

osm_combined <- osm_data_list %>% map(read_csv, show_col_types = FALSE) %>% bind_rows()

#write_rds(osm_combined, 'scratch/osm_combined.rds')


#osm_combined <- readRDS('scratch/osm_combined.rds')


hexagon_25km <- read_sf('scratch/25km_grid_hexagons.gpkg') %>% 
  st_transform(crs = 4326) %>% rowid_to_column('large_hexagon_id') %>% select('large_hexagon_id')

hexagon_north_america <- read_sf('data_directory/2km_hexagon_selection_grouped.gpkg')

for (i in 1:40) {
  osm_hexagon_aligned <- osm_combined %>% filter(group_id == i) %>% rowid_to_column()
  write_csv(osm_hexagon_aligned, paste0('scratch/osm_hexagon_grouped_csvs/hexagon_group_', i, '.csv'))
  print(paste('Finished reading data:', i))
  #
  divided_dataset <- tibble(x = seq(1:nrow(osm_hexagon_aligned)))
  num_groups = 10
  divided_dataset <- divided_dataset %>% mutate(grouping = (row_number()-1) %/% (n()/num_groups)) %>% 
    group_by(grouping) %>% summarize(min_x = min(x), max_x = max(x)) %>% select(-grouping)
  sequence_start = pull(divided_dataset, min_x)
  sequence_end = pull(divided_dataset, max_x)
  for (x in 1:10)  {
    group_slice <- osm_hexagon_aligned %>% 
      filter(rowid >= sequence_start[x] & rowid < sequence_end[x]) %>% 
      st_as_sf(coords = c('lon', 'lat'), crs = 4326)
    group_slice <- st_join(group_slice, hexagon_25km, left = TRUE)
    write_sf(group_slice, paste0('data_directory/osm_grouped/group_slice_section_', i,'_part_', x, '.gpkg'))
    print(paste('Completed: section', i, 'slice', x))
  }
}

for (i in 1:40) {
  hexagon_subset <- hexagon_north_america %>% filter(group_id == i)
  write_sf(hexagon_subset, paste0('data_directory/final_hexagon/osm_hexagon_aligned_', i, '.gpkg'))
  print(paste('Completed:', i))
}


```

```{r}

###

# Note: use 25 km grid to aggregate streets with same name, fill in gaps

###

osm_data_list = list.files('data_directory/osm_grouped/', 
                           pattern = 'group_slice_section_*',
                           full.names = TRUE,
                           recursive = TRUE)

hexagon_north_america <- read_sf('data_directory/2km_hexagon_selection_grouped.gpkg')



inner_fill <- function(osm_subset) {
  if (all(!is.na(osm_subset$lanes))) {
  } else {
    max_val_lanes <- max(osm_subset$lanes, na.rm = TRUE)
    osm_subset$lanes <- replace_na(osm_subset$lanes, max_val)
  }
  if (all(!is.na(osm_subset$max_speed))) {
  } else {
    max_val_speed <- max(osm_subset$max_speed, na.rm = TRUE)
    osm_subset$max_speed <- replace_na(osm_subset$max_speed, max_val_speed)
  }
}


fill <- function(osm_file) {
  osm_name_list <- read_sf(osm_file)
  osm_name_list <- osm_name_list %>% group_split(name)
  p  <- progressr::progressor(along = osm_name_list)
  hexagons_joined <- future_map(osm_name_list,   
                                ~{ p()
                                  inner_fill(.x)})
}

inner_summarizer <- function(osm_file, hexagons) {
  osm_iterate <- read_sf(osm_file) %>%
    select(-rowid, -point_id)
  hexagon_joined <- st_join(hexagons, osm_iterate,
                            left = TRUE,
                            join = st_intersects) %>% 
    st_drop_geometry()
  hexagon_sum <- hexagon_joined %>% group_by(rowid) %>% 
    summarize_at(c('max_speed', 'type', 'lanes'),
                 max, na.rm = TRUE)
  return(hexagon_sum)
}

summarizer <- function(osm_list, hexagons) {
  p  <- progressr::progressor(along = osm_list)
  hexagons_joined <- future_map(osm_list,
                                ~{ p()
                                  inner_summarizer(.x, hexagons = hexagons)},
                                globals = c(hexagons = hexagons))
}

###

options(future.globals.maxSize = 1.5e+9)

plan(callr, workers = 6)

osm_hexagon_template <- tibble(rowid = numeric(),
                               max_speed = numeric(),
                               type = character(),
                               lanes = numeric()
)

for (i in 1:40) {
  hexagon_selection <- read_sf(paste0('data_directory/final_hexagon/osm_hexagon_aligned_', i, '.gpkg'))
  osm_pattern <- paste0('group_slice_section_', i, '_*')
  osm_subsection = list.files('data_directory/osm_grouped/', 
                              pattern = osm_pattern,
                              full.names = TRUE,
                              recursive = TRUE)
  print(paste('Beginning subsection:', i))
  for (x in 1:10) {
    osm_iterate <- read_sf(osm_subsection[x]) %>%
      select(-rowid, -point_id)
    hexagon_joined <- st_join(hexagon_selection, osm_iterate,
                              left = TRUE,
                              join = st_intersects) %>% 
      st_drop_geometry()
    osm_hexagon_template <- bind_rows(osm_hexagon_template, hexagon_joined)
    print(paste('Completed subsection', i, 'group', x))
  }
  print(paste('Completed subsection:', i))
}

#write_rds(osm_hexagon_template, 'scratch/osm_hexagon_template.rds')

osm_hexagon_template <- read_rds('scratch/osm_hexagon_template.rds')

speed_sum <- osm_hexagon_template %>% rename(group_id = group_id.x) %>% 
  select(-group_id.y) %>% group_by(large_hexagon_id, type) %>% summarize_at(c('max_speed'),
                                                                            min, na.rm = TRUE)

lane_sum <- osm_hexagon_template %>% rename(group_id = group_id.x) %>% 
  select(-group_id.y) %>% group_by(large_hexagon_id, type) %>% summarize_at(c('lanes'),
                                                                            min, na.rm = TRUE)

test <- speed_sum %>% filter(large_hexagon_id == i & type == j) %>% 
  select(max_speed) %>% pull()

test <- lane_sum %>% filter(large_hexagon_id == i & type == j) %>% 
  select(max_speed) %>% pull()

###

divided_dataset <- tibble(x = seq(1:5549984))

num_groups = 200

divided_dataset <- divided_dataset %>% mutate(grouping = (row_number()-1) %/% (n()/num_groups)) %>% 
  group_by(grouping) %>% 
  summarize(min_x = min(x), max_x = max(x)) %>% select(-grouping)

sequence_start = pull(divided_dataset, min_x)

sequence_end = pull(divided_dataset, max_x)


for (i in 1:200)  {
  hexagon_slice <- osm_hexagon_template %>%
    filter(rowid >= sequence_start[i] & rowid < sequence_end[i])
  write_csv(hexagon_slice, paste0('data_directory/final_osm/final_osm_chunks/osm_row_table_chunk_', i, '.csv'))
  print(paste('Completed:', i))
}


###

tibbler <- function(tibblee) {
  to_be_tibbled <- read_csv(tibblee) %>%
    group_by(rowid)
  here_comes_the_tibbling <- to_be_tibbled %>% 
    summarize_at(c('max_speed', 'type', 'lanes'),
                 max, na.rm = TRUE)
  return(here_comes_the_tibbling)
}


tibble_summarizer <- function(csv_list) {
  p  <- progressr::progressor(along = csv_list)
  joined_csvs <- future_map(csv_list,
                            ~{ p()
                              tibbler(.x)})
}

osm_tibbles = list.files('data_directory/final_osm/final_osm_chunks/', 
                         pattern = 'osm_row_table_chunk_*',
                         full.names = TRUE,
                         recursive = TRUE)

osm_hexagon_append <- tibble(rowid = numeric(),
                             max_speed = numeric(),
                             type = character(),
                             lanes = numeric()
)

plan(callr, workers = 6)

for (i in 1:70)  {
  with_progress({osm_hexagon_tibbled <- tibbler(osm_tibbles[i])})
  osm_hexagon_append <- bind_rows(osm_hexagon_append, osm_hexagon_tibbled)
  print(paste('Completed:', i))
}

write_csv(osm_hexagon_append, 'data_directory/final_osm/final_osm_table_1.csv')

for (i in 70:135)  {
  with_progress({osm_hexagon_tibbled <- tibbler(osm_tibbles[i])})
  osm_hexagon_append <- bind_rows(osm_hexagon_append, osm_hexagon_tibbled)
  print(paste('Completed:', i))
}

write_csv(osm_hexagon_append, 'data_directory/final_osm/final_osm_table_2.csv')

for (i in 135:200)  {
  with_progress({osm_hexagon_tibbled <- tibbler(osm_tibbles[i])})
  osm_hexagon_append <- bind_rows(osm_hexagon_append, osm_hexagon_tibbled)
  print(paste('Completed:', i))
}

write_csv(osm_hexagon_append, 'data_directory/final_osm/final_osm_table_3.csv')


test <- read_csv(osm_tibbles[50])

###

osm_tibbles = list.files('data_directory/final_osm/', 
                         pattern = 'final_osm_table_*',
                         full.names = TRUE,
                         recursive = TRUE)

osm_hexagon_tibbled <- lapply(osm_tibbles, read_csv) %>% bind_rows()


hexagon_north_america <- read_sf('data_directory/2km_hexagon_selection_grouped.gpkg')

hexagon_north_america <- left_join(hexagon_north_america, osm_hexagon_tibbled, by = 'rowid')

hexagon_north_america <- hexagon_north_america %>% filter_all(all_vars(!is.infinite(max_speed)))

write_sf(hexagon_north_america, 'data_directory/final_osm_joined_hexagons/final_osm_joined_hexagons.gpkg')

hexagon_north_america <- hexagon_north_america %>% filter(rowAny(across(everything(), ~ !is.na(.x))))

```


# Cast lines between points

```{r}


# Credit: https://gis.stackexchange.com/questions/293658/creating-lines-between-pairs-of-points

library(tidyverse)
library(sf)

table_sf <- table %>%
  group_by(NOMBRE) %>%
  mutate(
    lineid = row_number(), # create a lineid
    LONG_end = lead(LONG), # create the end point coords for each start point
    LAT_end = lead(LAT)
  ) %>% 
  unite(start, LONG, LAT) %>% # collect coords into one column for reshaping
  unite(end, LONG_end, LAT_end) %>%
  filter(end != "NA_NA") %>% # remove nas (last points in a NOMBRE group don't start lines)
  gather(start_end, coords, start, end) %>% # reshape to long
  separate(coords, c("LONG", "LAT"), sep = "_") %>% # convert our text coordinates back to individual numeric columns
  mutate_at(vars(LONG, LAT), as.numeric) %>%
  st_as_sf(coords = c("LONG", "LAT")) %>% # create points
  group_by(NOMBRE, INT, lineid) %>%
  summarise() %>% # union points into lines using our created lineid
  st_cast("LINESTRING")

plot(table_sf[, 1:2])

```


```{r}

zm_bbox <- st_bbox(north_america_bbox)


buffer_plot <- ggplot() + geom_sf(data = land, fill = 'gray70', colour = 'gray15') +
  geom_sf(data = large_rivers, colour = 'gray60') +
  geom_sf(data = small_rivers, colour = 'gray60', alpha = 0.3) +
  geom_sf(data = large_lakes, fill = 'gray50', colour = 'gray15') +
  geom_sf(data = small_lakes, fill = 'gray50', colour = 'gray15') +
  geom_sf(data = zm_buffer_collected_test, aes(fill = buffer_dist)) +
  scale_fill_carto_d(palette = 'TealGrn', direction = -1, name = 'Buffer distance \n in km') +
  theme_dark(base_family = extrafont::choose_font('Cantarell Light'), 
             base_size = 12) +
  coord_sf(xlim = c(zm_bbox[[1]], zm_bbox[[3]]),
           ylim = c(zm_bbox[[2]], zm_bbox[[4]]), 
           expand = FALSE) 



```
