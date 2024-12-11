
execute_process(
COMMAND git rev-parse --abbrev-ref HEAD
WORKING_DIRECTORY "/home/oiran/srsran_split/srsRAN_Project-release_24_10"
OUTPUT_VARIABLE GIT_BRANCH
OUTPUT_STRIP_TRAILING_WHITESPACE
)

execute_process(
COMMAND git log -1 --format=%h
WORKING_DIRECTORY "/home/oiran/srsran_split/srsRAN_Project-release_24_10"
OUTPUT_VARIABLE GIT_COMMIT_HASH
OUTPUT_STRIP_TRAILING_WHITESPACE
)

message(STATUS "Generating build information")
configure_file(
  /home/oiran/srsran_split/srsRAN_Project-release_24_10/lib/support/versioning/hashes.h.in
  /home/oiran/srsran_split/srsRAN_Project-release_24_10/build/hashes.h
)
