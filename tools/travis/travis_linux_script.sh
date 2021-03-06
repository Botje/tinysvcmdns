#!/bin/bash
set -ev

if [ $ANALYZE = "true" ]; then
    echo "=== Running static code analysis ==="
    if [ "$CC" = "clang" ]; then
        mkdir -p build
        cd build
        scan-build cmake -G "Unix Makefiles" ..
        scan-build -enable-checker security.FloatLoopCounter \
          -enable-checker security.insecureAPI.UncheckedReturn \
          --status-bugs -v \
          make -j 8
        cd .. && rm build -rf
    else
        cppcheck --template "{file}({line}): {severity} ({id}): {message}" \
            --enable=style --force --std=c++11 -j 8 \
            --suppress=incorrectStringBooleanError \
            --suppress=invalidscanf --inline-suppr \
            -I *.c *.h 2> cppcheck.txt
        if [ -s cppcheck.txt ]; then
            echo "====== CPPCHECK Static Analysis Errors ======"
            cat cppcheck.txt
            exit 1
        fi
    fi
else
    echo "=== Building ==="

    # cross compilation only with gcc
    if [ "$CC" = "gcc" ]; then
        echo "Cross compile release build for MinGW 32 bit"
        mkdir -p build && cd build
        cmake -DCMAKE_TOOLCHAIN_FILE=../tools/cmake/Toolchain-mingw32.cmake -DCMAKE_BUILD_TYPE=Release ..
        make -j
        cd .. && rm build -rf

        echo "Cross compile release build for MinGW 64 bit"
        mkdir -p build && cd build
        cmake -DCMAKE_TOOLCHAIN_FILE=../tools/cmake/Toolchain-mingw64.cmake -DCMAKE_BUILD_TYPE=Release ..
        make -j
        cd .. && rm build -rf

        echo "Cross compile release build for 32-bit linux"
        mkdir -p build && cd build
        cmake -DCMAKE_TOOLCHAIN_FILE=../tools/cmake/Toolchain-gcc-m32.cmake -DCMAKE_BUILD_TYPE=Release ..
        make -j
        cd .. && rm build -rf
    fi

    if [ "$CC" = "gcc" ]; then
        echo "Upgrade to gcc 4.8"
        export CXX="g++-4.8" CC="gcc-4.8"
    fi

    echo "Compile release build for 64-bit linux"
    mkdir -p build && cd build
    cmake -DCMAKE_BUILD_TYPE=Release ..
    make -j
    cd .. && rm build -rf


    #this run inclides full examples and methodcalls
    echo "Debug build and unit tests (64 bit)"
    mkdir -p build && cd build
    cmake -DCMAKE_BUILD_TYPE=Debug -DMDNS_BUILD_UNIT_TESTS=ON -DMDNS_ENABLE_COVERAGE=ON ..
    make -j && make test ARGS="-V"
    # only run coveralls on main repo, otherwise it fails uploading the files
    echo "-> Current repo: ${TRAVIS_REPO_SLUG}"
    if ([ "$CC" = "gcc-4.8" ] || [ "$CC" = "gcc" ]) && ([ "${TRAVIS_REPO_SLUG}" = "Pro/tinysvcmdns" ]); then
        echo "  Building coveralls for ${TRAVIS_REPO_SLUG}"
        coveralls --gcov /usr/bin/gcov-4.8 -E '.*\.h' -E '.*CMakeCXXCompilerId\.cpp' -E '.*CMakeCCompilerId\.c' -r ../
    else
        echo "  Skipping coveralls since not gcc and/or ${TRAVIS_REPO_SLUG} is not the main repo"
    fi
    cd .. && rm build -rf
fi
