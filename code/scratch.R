

grid_centroids <- read_sf('/home/steven/Documents/common/thesis/ch2/gis_data/scratch/test/grid_centroids_filtered.gpkg')

grid_centroids <- grid_centroids %>% select(SURFACE, LANES, SPEEDLIM, CLASS) %>%
  rowid_to_column('uid')

tmp <- st_sfc()
class(tmp)[1] <- "sfc_LINESTRING"

pairwise_lines <- st_sf(uid_1 = character(0), uid_2 = character(0), 
                        node_id = character(0), length_m = numeric(0),
                        geometry = tmp) %>%
  st_set_crs('ESRI:102008')


for (i in 1:704589) {
  coord_one <- grid_centroids %>% filter(uid == i)
  print(paste('Starting uid:', i))
  inner_counter = 1
  for (j in 1:704589) {
    coord_two <- grid_centroids %>% filter(uid == j)
    combined <- rbind(coord_one, coord_two)
    line <- st_cast(st_union(combined), "LINESTRING") %>% st_as_sf() 
    line <- line %>% mutate(length_m = as.numeric(st_length(line)))
    uid_1_input = as.character(i)
    uid_2_input = as.character(j)
    node_id = paste0(uid_1_input, '_', uid_2_input)
    line  <- line %>% mutate(uid_1 = uid_1_input, uid_2 = uid_2_input,
                             node_id = node_id)
    if (line$length_m == 2000) {
      print(paste('Match! Appending:', i, j))
      pairwise_lines <- rbind(pairwise_lines, line)
    } else {print(paste('Skipping:', i, j))
    }
  }
  print(paste('Completed:', i))
}
