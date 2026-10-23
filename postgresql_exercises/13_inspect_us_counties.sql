SELECT * FROM us_counties_pop_est_2019;

SELECT county_name, state_name, us_counties_pop_est_2019.area_land
FROM us_counties_pop_est_2019
ORDER BY area_land DESC
LIMIT 3;

SELECT county_name, state_name, internal_point_lat, internal_point_lon
FROM us_counties_pop_est_2019
ORDER BY internal_point_lon DESC
LIMIT 5;