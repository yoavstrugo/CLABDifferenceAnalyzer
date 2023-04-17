#!/usr/bin/env bash
#/cs/course/current/labcc2/presubmit/ex2/io/TestIO_18.stdout
HUJI_DOMAIN=cs.huji.ac.il
HUJI_SERVERS=('river' 'bava')

STDOUT_SUFFIX=stdout
STDIN_SUFFIX=stdin
SSH_FLAGS="StrictHostKeyChecking=no"

PROGRAM_PREFIX="difference_analyzer_temp_"

CSE_USERNAME_VARNAME="CSE_USERNAME"
CSE_PASSWORD_VARNAME="CSE_PASSWORD"

function install_sshpass() {
  # installation of sshpass
  dpkg-query -l sshpass 1>/dev/null 2>/dev/null
  if [ $? -ne 0 ]; then
    echo "'sshpass' is not installed, installing..."
    sudo apt-get -y install sshpass 1>/dev/null
    if [ $? -eq 0 ]; then
      echo 'sshpass' succefully installed.
    else
      echo There was an error installing 'sshpass'
      exit 1
    fi
  fi
}

function user_creds() {
  local -n username_ref=$1
  local -n password_ref=$2

  if [[ ! -z "${CSE_USERNAME}" ]]
  then
    echo "Using username from environment variable CSE_USERNAME"
    username_ref="${CSE_USERNAME}"
  else
    echo -n "What is your CSE username? "
    # shellcheck disable=SC2034
    read -r username_ref
  fi

  if [[ ! -z "${CSE_PASSWORD}" ]]
  then
      echo "Using password from environment variable CSE_PASSWORD"
      password_ref=${CSE_PASSWORD}
  else
    echo -n "What is your CSE password? "
    # shellcheck disable=SC2034
    read -r -s password_ref
  fi
  echo
}

function program_information() {
  local -n executable_name_ref=$1
  local -n args_ref=$2

  echo -n "What is your executable name? "
  # shellcheck disable=SC2034
  read -r executable_name_ref

  echo -n -e "What are the arguments to pass to the program (seperated by\
 spaces)? "
  # shellcheck disable=SC2034
  read -r args_ref
}

function opening_screen() {
  echo First, make sure you have compiled your program
  echo In addition, you must be connected to \'eduroam\' wifi
  echo "If you have errors (permission error/access error), you may need to\
 run this with sudo. (i.e 'sudo difference_analyzer') [You may need to\
 enter password for the linux machine]"
  echo -n Press 'Enter' to continue, Ctrl-C to quit
  read -r
}

function input_file_name() {
  local -n school_stdin_path_ref=$1
  local -n school_stdout_path_ref=$2
  # shellcheck disable=SC2034
  local -n filename_ref=$3

  echo "Enter school stdout path (i.e /cs/course/current/labcc2/presubmit/ex1/io/TestIO_42.stdout)"
  read -r school_stdout_path_ref

  if [ "${school_stdout_path_ref##*.}" != "${STDOUT_SUFFIX}" ]; then
    echo Expected *.stdout file, please check your input.
    echo -n Press 'Enter' to try again, or Ctrl-C to abort.
    read -r _
    return 1
  fi

  school_file_without_prefix="${school_stdout_path_ref%%.*}"
  # shellcheck disable=SC2034
  school_stdin_path_ref="${school_file_without_prefix}"."${STDIN_SUFFIX}"

  filename=$(basename -- "$school_stdout_path_ref")
  filename="$PROGRAM_PREFIX${filename%.*}"

  return 0
}

function select_server() {
  local -n host_ref=$1
  local selected_server

  # Server selection
  echo Choose HUJI server number
  i=0
  for server in "${HUJI_SERVERS[@]}"; do
    echo -n -e "$server = $i\t"
    i+=1
  done
  echo

  read -r selected_server
  # shellcheck disable=SC2034
  host_ref="${HUJI_SERVERS["$selected_server"]}.$HUJI_DOMAIN"
}

function copy_file() {
  local host=$1
  local password=$2
  local username=$3
  local file=$4
  local output=$5
  local can_be_empty=$6

  echo Copying "$file" from "$host"

  sshpass -p "$password" scp -r -o "$SSH_FLAGS" \
    "$username"@"$host":"$file" \
    "$output" 1>/dev/null

  if [ ! -f "$output" ]; then
    echo "$file" haven\'t been copied for unknown reason.
    echo Maybe try to check your login info, change server, or just try again.
    exit 1
  fi

  if [ "$can_be_empty" ]; then
    return 0
  fi

  if [ ! -s "$output" ]; then
    echo ERROR: Input file is empty.
    echo Try to log onto the "$host" and look for "$file".
    echo
    echo To log to the remote machine run \'ssh -l \<cse username\> $host\' and enter your cse password.
    echo Then run \'cat "$file"\' and \'file "$file"\' to check the
    status of the file.
    exit 1
  fi
}

function run_program() {
  local program=$1
  local args=$2
  local redirected_input=$3
  local redirected_output=$4

  echo Running your program with the schools input
  ./${program} "$args" <"$redirected_input" >"$redirected_output"
  sleep 2
}

function find_differences() {
  local my_file=$1
  local their_file=$2
  local output=$3

  diff -ys "$my_file" "$their_file" \
    >"$filename-compare-temp"
  res=$?

  if [ $res -eq 0 ]; then
    echo Files are identical
    echo Press 'Enter' to see outputs comparisons, Ctrl-C to quit
    read -r _
  elif [ $res -eq 1 ]; then
    echo There are differences. Press 'Enter' to see them
    read -r _
  else
    echo An error has occured while comparing, aborting.
    exit 1
  fi

  echo Comparing outputs, left is yours, right is theirs >"$output"
  echo Press Enter to scroll >>"$output"
  echo >>"$output"
  cat "$filename-compare-temp" >>"$output"
  rm "$filename-compare-temp"
}

function exit_message() {
    echo "You may remove all files beginning with '${PROGRAM_PREFIX}'"
}

opening_screen

install_sshpass
install_iselect
clear

user_creds username password

program_information executable_name args

input_file_name school_stdin_path school_stdout_path filename
while [ $? -eq 1 ]; do
  input_file_name school_stdin_path school_stdout_path filename
done

select_server host

trap "exit_message; exit 0;" INT

LOCAL_INPUT_FILE="$filename"."$STDIN_SUFFIX"
LOCAL_OUTPUT_FILE="$filename"."$STDOUT_SUFFIX"

# shellcheck disable=SC2154
copy_file "$host" "$password" "$username" "$school_stdin_path" \
  "$LOCAL_INPUT_FILE" 0

# shellcheck disable=SC2154
copy_file "$host" "$password" "$username" "$school_stdout_path" \
  "$LOCAL_OUTPUT_FILE" 0

LOCAL_MY_OUTPUT_FILE="$filename-my.$STDOUT_SUFFIX"

# shellcheck disable=SC2154
run_program "$executable_name" "$args" "$LOCAL_INPUT_FILE" "$LOCAL_MY_OUTPUT_FILE"

DIFF_FILE="$filename.comp"
find_differences "$LOCAL_MY_OUTPUT_FILE" "$LOCAL_OUTPUT_FILE" "$DIFF_FILE"

more "$DIFF_FILE"


echo
echo Compare file is "$DIFF_FILE" for you to look at it again.
exit_message
exit 0

