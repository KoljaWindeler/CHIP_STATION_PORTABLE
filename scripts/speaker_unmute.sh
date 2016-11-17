LABEL_FILE=`grep -l pcf8574a /sys/class/gpio/*/*label`
BASE_FILE=`dirname $LABEL_FILE`/base
BASE=`cat $BASE_FILE`
let PIN=$BASE+4
echo $PIN > /sys/class/gpio/export
D="gpio"$PIN
echo "out" > /sys/class/gpio/$D/direction
echo 1 > /sys/class/gpio/$D/value
