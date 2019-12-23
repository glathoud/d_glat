#!/usr/bin/env bash

# Parallel compilation of D code
# By Guillaume Lathoud, 2019
# The Boost License applies, as described in file ./LICENSE
#
# Usage: dpaco.sh [<...options...>] file_a.d dir_b file_c.d file_d.b dir_e

set -e

# --- read options

COMPILER="$(which -a ldmd2 dmd | head -1)"
EXEC=""
EXEC_OPT=""
FORCE=""
MODE="release" # debug release relbug relbug0
OUTBIN="dpaco.bin"
PARALLEL_OPT=""

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

# --- setup constants

if [ "$COMPILER_OPT" = "" ]; then

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

OBJDIR="${BASEDIR}/.${ME}__$(basename ${OUTBIN})__${MODE}"

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

# --- Do them all!

function src_list_all
{
    for src in "${SRCLIST[@]}"
    do
        if [ -f "$src" ]; then
            
            echo "$src" ;
        elif [ -d "$src" ]; then
            find -L "$src" -name '*.d' ;

        else
            echo "Could not find or don't what to do with src: '${src}'" 1&>2 ;
            exit 4 ;
        fi
    done   
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
    
    echo "$TMP"
}

function do_one()
{
    FILENAME=$1
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
}


export -f D_module_dotname
export -f do_one

echo
echo "Compiling each file separately..."
set -v
time {
    src_list_all | parallel -k --ungroup --halt now,fail=1 do_one {} "$OBJDIR" "$COMPILER" "$TIMESUMMARY" "$COMPILER_OPT"  ||  exit 6
    echo
    echo
    echo "Done compiling each file separately."
}
set +v

O_LIST="$(echo $(find ${OBJDIR} -name '*.o'))"

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
    time ${CMD[@]}
fi

ls -l "$OUTBIN"

cat "$TIMESUMMARY" | sort > "$TIMESUMMARY.sorted"

# Done, display some info

set -v
cat /proc/$$/status  | grep VmHWM

wc -l "$TIMESUMMARY.sorted"
tail -10 "$TIMESUMMARY.sorted"
set +v

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
