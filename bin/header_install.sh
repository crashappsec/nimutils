#!/bin/bash

function color {
    case $1 in
        black)   CODE=0 ;;
        red)     CODE=1 ;; RED)     CODE=9 ;;
        green)   CODE=2 ;; GREEN)   CODE=10 ;;
        yellow)  CODE=3 ;; YELLOW)  CODE=11 ;;
        blue)    CODE=4 ;; BLUE)    CODE=12 ;;
        magenta) CODE=5 ;; MAGENTA) CODE=13 ;;
        cyan)    CODE=6 ;; CYAN)    CODE=14 ;;
        white)   CODE=7 ;; WHITE)   CODE=15 ;;
        grey)    CODE=8 ;; *)       CODE=$1 ;;
    esac
    shift

    echo -n $(tput setaf ${CODE})$@$(tput op)
}

function colorln {
    echo $(color $@)
}

function to_abs_dir {
    pushd $1 > /dev/null
    echo `pwd`
    popd > /dev/null
}

SRC_DIR=$(to_abs_dir ${NIMUTILS_DIR:-.}/nimutils/c)
DST_DIR=${HEADER_DIR:-~/.local/c0/include}

mkdir -p $DST_DIR

DST_DIR=$(to_abs_dir $DST_DIR)

function copy_news {
    # $1 -- source directory
    # $2 -- destination directory
    # $3 -- file name.

    SRC_FILE=$1/$3
    DST_FILE=$2/$3

    if [[ $SRC_FILE -nt $DST_FILE ]]; then
        if [[ ! -e $SRC_FILE ]]; then
            echo $(color RED error:) specified 'cp ${SRC_FILE} ${DST_FILE}' but the source file does not exist.
        else
            if [[ ! -e $DST_FILE ]]; then
                echo $(color YELLOW "Copying new file: ") $3
                echo $(color YELLOW to: ) $DST_FILE
            else
                echo $(color GREEN "Updating file:" ) $3
                echo $(color GREEN full location: $DST_FILE)
            fi
            cp $SRC_FILE $DST_FILE
        fi
    fi
}

function push_ext_files {
    # $1 is the src dir
    # $2 is the dst dir
    # $3 is the extension
    pushd $1 >/dev/null

    for item in `ls *.$3`; do
        copy_news $1 $2 $item
    done

    popd >/dev/null
}

push_ext_files ${SRC_DIR} ${DST_DIR} h
