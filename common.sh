function run_or_exit {
	MSG=$1; CMD=$2;
	echo $MSG;
	echo "$CMD";
	$CMD
	if [ $? -ne 0 ]; then
		echo "Failed with exit status: $?"
		exit 1
	fi
	echo "----"
}
