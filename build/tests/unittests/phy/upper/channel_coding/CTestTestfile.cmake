# CMake generated Testfile for 
# Source directory: /home/oiran/srsran_split/srsRAN_Project-release_24_10/tests/unittests/phy/upper/channel_coding
# Build directory: /home/oiran/srsran_split/srsRAN_Project-release_24_10/build/tests/unittests/phy/upper/channel_coding
# 
# This file includes the relevant testing commands required for 
# testing this directory and lists subdirectories to be tested as well.
add_test(crc_calculator_test "crc_calculator_test" "-F" "lut")
set_tests_properties(crc_calculator_test PROPERTIES  _BACKTRACE_TRIPLES "/home/oiran/srsran_split/srsRAN_Project-release_24_10/tests/unittests/phy/upper/channel_coding/CMakeLists.txt;26;add_test;/home/oiran/srsran_split/srsRAN_Project-release_24_10/tests/unittests/phy/upper/channel_coding/CMakeLists.txt;0;")
subdirs("polar")
subdirs("ldpc")
subdirs("short")
set_directory_properties(PROPERTIES LABELS "phy")
