#!/usr/bin/env bash
function doit {
    echo $1
    rdmd --force -debug -inline -O --main -unittest $1
}
export -f doit

find . -name '*.d' | xargs -n 1 grep -l unittest | xargs -n 1 bash -c 'doit "$@"' _
RESULT=$?

echo $1

if [[ $RESULT == 0 ]]
then
    if [[ "$1" == "-rec" ]]
    then
	function do_other {
	    if [[ "$1" ]]
	    then
		echo "$1"
		$1
	    fi
	}
	export -f do_other
	find . -mindepth 2 -name 'unittest.sh' | xargs -n 1 bash -c 'do_other "$@"' _
	RESULT=$?
    fi
fi

echo
echo "----------------------------------------"
echo "Done: $(realpath $0)"
if [[ $RESULT == 0 ]]
then
    echo "=> Success!"
else
    echo "=> Failure! (result: $RESULT)"
fi

exit $RESULT
