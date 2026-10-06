CXX ?= c++
CXXFLAGS ?= -std=c++17 -O2 -Wall -Wextra -Werror -pedantic -pthread
.PHONY: test clean
test: build/core-tests
	./build/core-tests
build/core-tests: Sources/ToneCore/ToneCore.cpp Sources/ToneCore/Fingerprint.cpp Sources/ToneCore/include/ToneCore.h Tests/ToneCoreTests/main.cpp
	mkdir -p build
	$(CXX) $(CXXFLAGS) -ISources/ToneCore/include Sources/ToneCore/ToneCore.cpp Sources/ToneCore/Fingerprint.cpp Tests/ToneCoreTests/main.cpp -o $@
clean:
	rm -f build/core-tests
