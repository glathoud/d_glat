#!/usr/bin/env bash

# Practical parallel compilation of D code,
# without fiddling around with a build system.
#
# By Guillaume Lathoud, 2019, 2020 and later
# The Boost License applies, as described in file ./LICENSE
#
# Usage: dpaco.sh [<...options...>] [file0.d dir1 file2.d file3.d dir4]
#
# Note that the options are written WITHOUT equal sign '='
# i.e.:
#     dpaco.sh --compiler <path_to_compiler> ...
# and NOT:
#     dpaco.sh --compiler=<path_to_compiler> ...
#
# Example: 
#     dpcao.sh --compiler ../my/compiler/ldmd2 --mode debug main.d lib_0 lib_1
#
# Example without specifying the source files/dirs 
# => will grab all available files/dirs in the current path:
#     dpcao.sh --compiler ../my/compiler/ldmd2 --mode debug

ME_0=${0}
MY_ARGS=$@
echo $ME

set -e

# --- read options

COMPILER="$(which -a ldmd2 dmd | head -1)"
EXEC=""
EXEC_OPT=""
FORCE=""
FRESH_CHUNK_SIZE=50
MODE="" # debug release relbug relbug0
OUTBIN="dpaco.bin"
PARALLEL_OPT=""
SYSID="$(cat /etc/machine-id)_$(uname -a | sed 's/[^0-9]//g' | echo "ibase=10; obase=16; $(cat)" | bc)"

SRCLIST=()
while [[ $# -gt 0 ]]
do
    key="$1"
    case $key in
        -c|--compiler)
            COMPILER="$2"
            shift
            shift
            ;;
        -co|--compiler-opt)
            COMPILER_OPT="$2"
            shift
            shift
            ;;
        -fcs|--fresh-chunk-size)
            FRESH_CHUNK_SIZE="$2"
            shift
            shift
            ;;
        -d|--debug) # shortcut for -m=debug
            MODE="debug"
            shift
            ;;
        -e|--exec_opt)
            EXEC_OPT="$2"
            EXEC="exec"
            shift
            shift
            ;;
        -f|--force)
            FORCE="force"
            shift
            ;;
        -of|--output-file)
            OUTBIN="$2"
            shift
            shift
            ;;
        -j|--max-procs)  # e.g. -j=N to run parallel with N processes
            PARALLEL_OPT=" -j $2"
            shift
            shift
            ;;
        -m|--mode) # debug relbug0 relbug release
            MODE="$2"
            shift
            shift
            ;;
        *)    # unknown option
            SRCLIST+=("$1") # save it in an array for later
            shift # past argument
            ;;
    esac
done

# --- default SRCLIST

if [ "$SRCLIST" == "" ]; then
    OIFS=$IFS
    IFS=$'\n'
    SRCLIST=($(ls --hide='*~'))
    IFS=$OIFS
fi

# --- setup constants

if [ "$COMPILER_OPT" = "" ]; then

    if [ "$MODE" = "" ]; then
        MODE="release" # default
    fi
    
    if [ "$MODE" = "debug" ]; then
        COMPILER_OPT=" -debug -g -gs -gf -link-defaultlib-debug "

    elif [ "$MODE" = "relbug0" ]; then
        COMPILER_OPT=" -release -g -gs -gf -link-defaultlib-debug"
        
    elif [ "$MODE" = "relbug" ]; then
        COMPILER_OPT=" -release -g -gs -gf -link-defaultlib-debug -inline -O"
        
    elif [ "$MODE" = "release" ]; then
        COMPILER_OPT=" -release -inline -O "
        
    else
        echo "Bug with MODE: $MODE" 1>&2
        exit 1
    fi

elif [ "$MODE" != "" ]; then
    echo "Setting both COMPILER_OPT ($COMPILER_OPT) and MODE ($MODE) is forbidden, choose one or the other." 1>&2
    exit 2
fi


if [ "$OUTBIN" = "" ]; then
    echo "OUTBIN must be set (-of=...)" 1>&2
    exit 3
fi

BASEDIR=$(dirname "${OUTBIN}")

echo "BASEDIR:      $BASEDIR"
echo "COMPILER:     $COMPILER"
echo "COMPILER_OPT: '${COMPILER_OPT[@]}'"
if [ "$EXEC" != "" ]; then
    echo "EXEC:         $EXEC"
    echo "EXEC_OPT:     $EXEC_OPT"
fi
if [ "$FORCE" != "" ]; then
    echo "FORCE:        $FORCE"
fi
echo "MODE:         $MODE"
echo "OUTBIN:       $OUTBIN"
if [ "$PARALLEL_OPT" != "" ]; then
    echo "PARALLEL_OPT: '$PARALLEL_OPT'"
fi
echo "SRCLIST:      ${SRCLIST[@]}"
echo "."

ME_EXT=$(basename $0)
ME=${ME_EXT%.*}
#echo "ME: $ME"

COMPILID="$(echo $COMPILER_OPT | sed 's/[^-\+_a-zA-Z0-9]/_/g')"
OBJDIR="${BASEDIR}/.${ME}__$(basename ${OUTBIN})__${COMPILID}__${SYSID}"

TIMESUMMARY="${OBJDIR}/0_TIMESUMMARY.TXT"

echo "OBJDIR: $OBJDIR"

# --- prepare OBJDIR

if [ "$FORCE" ]
then
    rm -rf "${OBJDIR}" "${OUTBIN}" 2>>/dev/null
fi

if [ ! -d "${OBJDIR}" ]
then
    mkdir -p ${OBJDIR}
fi

FRESH="true"
if (( 1==$FRESH_CHUNK_SIZE ))  ||  $(ls -1qA "${OBJDIR}" | grep -q . )
then
    FRESH="false"
fi

echo "FRESH: ${FRESH},  FRESH_CHUNK_SIZE:${FRESH_CHUNK_SIZE}"

# --- Do them all!

function src_list_all()
{
    for src in "${SRCLIST[@]}"
    do
        if [ -f "$src" ]; then
            echo "$src" ;

        elif [ -d "$src" ]; then
            find -L "$src" -name '*.d'

        else
            >&2 echo "Could not find or don't what to do with src: '${src}'"  ;
            exit 4 ;
        fi
    done   
}

function src_list_all_uniq()
{
    src_list_all | xargs -n 1 realpath | sort | uniq
}

function src_list_chunks()
{
    LIST_ALL="$(src_list_all_uniq)"
    LIST_LIB="$(grep -L 'main(' ${LIST_ALL})"
    LIST_MAIN="$(grep -l 'main(' ${LIST_ALL})"
    xargs -n $FRESH_CHUNK_SIZE <<<"$LIST_LIB"
    xargs -n 1 <<<"$LIST_MAIN"
}


function D_module_dotname()
{
    FILENAME="$1"
    TMP=$( grep -m1 -E 'module [^;]+?;'  "$FILENAME" | cut -f 2 -d ' ' | cut -f 1 -d ';' )
    TMP="${TMP##*( )}"
    TMP="${TMP%%*( )}"

    if [ "$TMP" = "" ]
    then
        TMP="${FILENAME%.*}"
    fi
    
    echo "$(basename $TMP)"
}

function do_chunk()
{
    CHUNK="$1"
    if [ "$CHUNK" != "" ]
    then
        OBJDIR=$2
        COMPILER=$3
        COMPILER_OPT=${@:4}
        CMD_CHUNK="nice --adjustment 5 $COMPILER -c -oq -od=$OBJDIR ${COMPILER_OPT} $CHUNK"
        ${CMD_CHUNK[@]}
    fi
}

function do_one()
{
    FILENAME="$1"
    if [ "$FILENAME" != "" ]
    then
        DOTNAME=$( D_module_dotname "$FILENAME" )
        OBJDIR=$2
        COMPILER=$3
        TIMESUMMARY=$4
        COMPILER_OPT=${@:5}
        
        OBJFILENAME="${OBJDIR}/$DOTNAME.o"
        TIMEFILENAME="${OBJFILENAME}.time"
        
        # test .o: empty or old
        if [ ! -s "$OBJFILENAME" ] || [ "$OBJFILENAME" -ot "$FILENAME" ]
        then
            CMD_ONE="nice --adjustment 5 $COMPILER -c -oq -od=$OBJDIR ${COMPILER_OPT} $FILENAME"
            echo
            echo ${CMD_ONE[@]}
            {
                {
                    time ${CMD_ONE[@]} ;
                } 2> "${TIMEFILENAME}"
            } || {
                echo
                echo "Could not compile, reason:"
                cat "${TIMEFILENAME}"
                exit 5
            }
            
            TIMEUSER=$( head -3 "${TIMEFILENAME}" | tail -1 | cut -f 2 | sed 's/m\([0-9]\),/m0\1,/' )
            echo "$TIMEUSER $DOTNAME" >> "$TIMESUMMARY"
        else
            echo -n '#'
        fi
    fi
}


export -f D_module_dotname
export -f do_chunk
export -f do_one


if [ "$FRESH" == "true" ]
then
    echo
    echo "Compiling files grouped in chunks..."
    set -v
    time {
        src_list_chunks | parallel -k --ungroup --halt now,fail=1 do_chunk {} "$OBJDIR" "$COMPILER" "$COMPILER_OPT" ||  exit 6
    }
    set +v
    echo
    echo 
    echo "Done compiling files grouped in chunks."
else
    echo
    echo "Compiling each file separately..."
    set -v
    time {
        src_list_all_uniq | parallel -k --ungroup --halt now,fail=1 do_one {} "$OBJDIR" "$COMPILER" "$TIMESUMMARY" "$COMPILER_OPT"  ||  exit 7
    }
    set +v
    echo
    echo
    echo "Done compiling each file separately."
fi

O_LIST="$(echo $(find -L ${OBJDIR} -name '*.o'))"

O_LATEST="$(ls -rt ${O_LIST[@]} | tail -1)"

if [ -f "$OUTBIN" ]  &&  [ "$OUTBIN" -ot "$O_LATEST" ]
then
    rm "$OUTBIN" 2>>/dev/null
fi

if ! [ -f "$OUTBIN" ]
then
    CMD=( $COMPILER -oq -od="$OBJDIR" -of="$OUTBIN" ${COMPILER_OPT} $O_LIST )
    echo
    #echo ${CMD[@]}
    echo "============================================="
    echo "    Linking everything into ${OUTBIN}..."
    echo "============================================="
    set +e
    time { ERROR=$(${CMD[@]} 2>&1 > /dev/null); }
    code=$?
    if [ $code != 0 ]
    then
        # Deal with ERRORS due to the FRESH_CHUNK implementation
        # We do all this for compilation speed...
        echo "ERROR:"
        echo "$ERROR"
        echo 
        TO_DELETE=$(grep -o -e '^[^:]*\.o' <<<$ERROR | grep -v '\.\.' | grep -v -e '^/usr/')
        
        echo
        echo "TO_DELETE:"
        echo "$TO_DELETE"
        echo
        
        if [ "$TO_DELETE" != "" ]
        then
            echo "Workaround for FRESH_CHUNK-related issue: about to delete:"
            echo $TO_DELETE
            RM_CMD="rm $(echo $TO_DELETE)"
            echo
            echo "RM_CMD:"
            echo $RM_CMD
            echo
            ${RM_CMD[@]}
            echo "Workaround for FRESH_CHUNK-related issue: about to restart myself"
            RESTART="$ME_0 ${MY_ARGS[@]}"
            echo
            echo $RESTART
            ${RESTART[@]}
            exit 0
        fi
        exit 8
    fi
    set -e
fi

echo
ls -l "$OUTBIN"

if [ -f "$TIMESUMMARY" ]; then

    cat "$TIMESUMMARY" | sort > "$TIMESUMMARY.sorted"
    
    # Done, display some info

    echo
    wc -l "$TIMESUMMARY.sorted"
    echo "...of which the worst compilation times are:"
    tail -10 "$TIMESUMMARY.sorted"
fi

# Optionally start the executable

if [ "$EXEC" != "" ]
then
    echo
    echo "============================================="
    echo "    About to launch ${OUTBIN}..."
    echo "============================================="
    echo
    "${OUTBIN}" "{EXEC_OPT[@]}"
fi
