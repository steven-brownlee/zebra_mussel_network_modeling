library(sf)
library(tidyverse)

zm_occ <- read_csv('/home/steven/Documents/common/thesis/ch2/gis_data/downloads/zebra_mussel_occurrences/NAS-Specimen-Download.csv')

zm_occ <- zm_occ %>% select(`Scientific Name`, Longitude, Latitude, Accuracy, Status) %>% drop_na()

zm_occ_sf <- st_as_sf(zm_occ, coords = c('Longitude', 'Latitude'),
                   crs = st_crs(4326)) 

write_sf(zm_occ_sf, '/home/steven/Documents/common/thesis/ch2/gis_data/data_directory/dreissnid_occurrences.gpkg')

road_network <- read_sf('/home/steven/Downloads/NTAD_North_American_Roads_2691167086962748384.gpkg')

road_network <- road_network %>% filter(SURFACE == 'Unpaved' | SURFACE == 'Paved')

write_sf(road_network, '/home/steven/Documents/common/thesis/ch2/gis_data/data_directory/usdot_road_network.gpkg')

boundaries <- st_read('/home/steven/Downloads/politicalboundaries_shapefile/PoliticalBoundaries_Shapefile/NA_PoliticalDivisions/data/bound_p/boundaries_p_2021_v3.shp')

boundaries <- st_make_valid(boundaries)

boundaries <- boundaries %>% st_transform(crs = 4326)

coastline <- boundaries %>% st_union() %>% st_as_sf() %>% st_make_valid()

coastline <- st_as_sf(coastline) 

write_sf(boundaries, '/home/steven/Documents/common/thesis/ch2/gis_data/data_directory/cec_political_boundaries.gpkg')

write_sf(coastline, '/home/steven/Documents/common/thesis/ch2/gis_data/data_directory/cec_coastline.gpkg')

pop_places <- read_sf('/home/steven/Downloads/populatedplaces_shapefile/PopulatedPlaces_Shapefile/NA_Populated_Places/data/popPlaces_v2.shp')

pop_places <- pop_places %>% st_make_valid %>%st_transform(crs = 4326) %>% st_intersection(coastline)

lakes <- read_sf('/home/steven/Downloads/rivers_and_lakes_shapefile/NA_Lakes_and_Rivers/data/lakes_p/northamerica_lakes_cec_2023.shp')

lakes <- lakes %>% st_transform(crs = 4326) %>% st_make_valid()

write_sf(lakes, '/home/steven/Documents/common/thesis/ch2/gis_data/data_directory/cec_lakes.gpkg')

