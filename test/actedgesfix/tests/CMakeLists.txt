add_executable( test_parser test_parser.cpp ../src/parser.cpp ../src/lexer.cpp )
add_test( NAME test_parser COMMAND test_parser )
