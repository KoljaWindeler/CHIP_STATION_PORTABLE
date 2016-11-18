#!/bin/bash
# This script is mainly copied from 
# https://raw.githubusercontent.com/fordsfords/blink/gh-pages/blink.sh
# written by Steven Ford
#
# Copyright 2016 Kolja Windeler http://chipdipshop.de and licensed
# "public domain" style under
# [CC0](http://creativecommons.org/publicdomain/zero/1.0/): 
# 
# To the extent possible under law, the contributors to this project have
# waived all copyright and related or neighboring rights to this work.
# In other words, you can use this code for any purpose without any
# restrictions.  This work is published from: United States.  The project home
# is https://github.com/fordsfords/blink/tree/gh-pages


blink_cleanup()
{
  # Only un-export ports that we actually exported.
  if [ -n "$WARN_BATTERY_GPIO" ]; then gpio_unexport $WARN_BATTERY_GPIO; fi
  if [ -n "$CHR_LED_GPIO" ]; then gpio_unexport $CHR_LED_GPIO; fi
}


blink_stop()
{
  blink_cleanup
  echo "blink: stopped"
  exit
}

blink_error()
{
  blink_cleanup
  while [ -n "$1" ]; do :
    echo "blink: $1"
    shift    # get next error string into $1
  done
 # exit 1
}


check_i2c_installed()
{
  # Need to communicate with AXP209 via I2C commands
  if [ ! -x /usr/sbin/i2cget -o ! -x /usr/sbin/i2cset ]; then :
    blink_error "need i2c-tools for MON_RESET" "Use: sudo apt-get install i2c-tools"
  fi
}

gpio_export()
{
  # Accept numeric argument
  if echo "$1" | egrep '^[0-9][0-9]*$' >/dev/null; then :
    GPIO=$1
  elif [ -n "${GPIO_HASH[$1]}" ]; then :
    GPIO=${GPIO_HASH[$1]}
  else :
    echo "gpio_export: unrecognized GPIO ID '$1'" >&2
    return
  fi
  echo $GPIO >/sys/class/gpio/export
  echo "export "$GPIO
  return $?
}

gpio_unexport()
{
  # Accept numeric argument
  if echo "$1" | egrep '^[0-9][0-9]*$' >/dev/null; then :
    GPIO=$1
  elif [ -n "${GPIO_HASH[$1]}" ]; then :
    GPIO=${GPIO_HASH[$1]}
  else :
    echo "gpio_unexport: unrecognized GPIO ID '$1'" >&2
    return
  fi
  echo $GPIO >/sys/class/gpio/unexport
  return $?
}

gpio_unexport_all()
{
  for F in /sys/class/gpio/gpio[0-9]*; do :
    if [ -d "$F" ]; then :
      # strip off all of the path up to the first digit.
      GPIO=`echo $F | sed 's/^[^0-9]*//'`
      echo $GPIO >/sys/class/gpio/unexport
    fi
  done
}

gpio_direction()
{
  # Accept numeric argument
  if echo "$1" | egrep '^[0-9][0-9]*$' >/dev/null; then :
    GPIO=$1
  elif [ -n "${GPIO_HASH[$1]}" ]; then :
    GPIO=${GPIO_HASH[$1]}
  else :
    echo "gpio_direction: unrecognized GPIO ID '$1'" >&2
    return
  fi
  echo $2 >/sys/class/gpio/gpio${GPIO}/direction
  return $?
}

gpio_output()
{
  # Accept numeric argument
  if echo "$1" | egrep '^[0-9][0-9]*$' >/dev/null; then :
    GPIO=$1
  elif [ -n "${GPIO_HASH[$1]}" ]; then :
    GPIO=${GPIO_HASH[$1]}
  else :
    echo "gpio_output: unrecognized GPIO ID '$1'" >&2
    return
  fi
  echo $2 >/sys/class/gpio/gpio${GPIO}/value
  return $?
}

gpio_input()
{
  # Accept numeric argument
  if echo "$1" | egrep '^[0-9][0-9]*$' >/dev/null; then :
    GPIO=$1
  elif [ -n "${GPIO_HASH[$1]}" ]; then :
    GPIO=${GPIO_HASH[$1]}
  else :
    echo "gpio_input: unrecognized GPIO ID '$1'" >&2
    return
  fi
  VAL=`cat /sys/class/gpio/gpio${GPIO}/value`
  return $VAL
}


read_config()
{
	XIO_LABEL_FILE=`grep -l pcf8574a /sys/class/gpio/*/*label`
	XIO_BASE_FILE=`dirname $XIO_LABEL_FILE`/base
	XIO_BASE=`cat $XIO_BASE_FILE`
	echo "Base is "$XIO_BASE

	MON_RESET=1  # shutdown on button press

	MON_BATTERY=5 # shutdown on empty (5%) battery
	WARN_BATTERY=65 # blink at 10% remaining battery life
  
	WARN_BATTERY_GPIO=$(($XIO_BASE+6)) # blink on pin p6
	WARN_BATTERY_DEFAULT_VALUE=1 # led is ON when NOT warning (blinking)
	WARN_BATTERY_LED_STATUS=
  
	CHR_LED_GPIO=$(($XIO_BASE+7)) # charge LED on pin p7
	CHR_LED_DEFAULT_VALUE=0 # led is OFF when NOT charging
	CHR_LED_STATUS=
}


# Group init functions related to GPIO
init_chr_gpio()
{
  if [ -n "$CHR_LED_GPIO" ]; then :
    gpio_export $CHR_LED_GPIO; ST=$?
    if [ $ST -ne 0 ]; then :
      blink_error "cannot export $CHR_LED_GPIO for blinking (in use?)"
    fi
    gpio_direction $CHR_LED_GPIO out

    CHR_LED_STATUS=$CHR_LED_DEFAULT_VALUE
    gpio_output $CHR_LED_GPIO $CHR_LED_STATUS
  fi
}

invert_chr_gpio()
{
  if [ -n "$CHR_LED_GPIO" ]; then :
    CHR_LED_STATUS=$((1-CHR_LED_STATUS))
    gpio_output $CHR_LED_GPIO $CHR_LED_STATUS
	echo "set chr: $CHR_LED_STATUS"
  fi
}

invert_pwr_gpio()
{
  if [ -n "$WARN_BATTERY_GPIO" ]; then :
    WARN_BATTERY_LED_STATUS=$((1-WARN_BATTERY_LED_STATUS))
	gpio_output $WARN_BATTERY_GPIO $WARN_BATTERY_LED_STATUS
	echo "set pwr: $WARN_BATTERY_LED_STATUS"
  fi
}



# Group init functions related to I2C
init_mon_reset()
{
  if [ -n "$MON_RESET" ]; then :
    check_i2c_installed
    MON_RESET_SAMPLE=
  fi
}

sample_mon_reset()
{
  if [ -n "$MON_RESET" ]; then :
    REG4AH=$(i2cget -f -y 0 0x34 0x4a)  # Read AXP209 register 4AH
    BUTTON=$(( $REG4AH & 0x02 ))        # mask off the short press bit
    if [ $BUTTON -eq 0 ]; then :
      MON_RESET_SAMPLE=0
    else :
      MON_RESET_SAMPLE=1
    fi
  fi
}

check_shut_reset()
{
  if [ -n "$MON_RESET" ]; then :
    if [ $MON_RESET_SAMPLE -eq 1 ]; then :
      shutdown_now "reset"
    fi
  fi
}


init_mon_battery()
{
  if [ -n "$MON_BATTERY" ]; then :
    check_i2c_installed

    if [ -n "$WARN_BATTERY_GPIO" ]; then :
      gpio_export $WARN_BATTERY_GPIO; ST=$?
      if [ $ST -ne 0 ]; then :
        blink_error "cannot export $WARN_BATTERY_GPIO for battery warning (in use?)"
      fi
      WARN_BATTERY_GPIO_SET=1
      gpio_direction $WARN_BATTERY_GPIO out

      # Assume no warning
      gpio_output $WARN_BATTERY_GPIO $WARN_BATTERY_DEFAULT_VALUE
    fi

    # force ADC enable for battery voltage and current
    i2cset -y -f 0 0x34 0x82 0xC3

    MON_BATTERY_SAMPLE_PWR=
    MON_BATTERY_SAMPLE_PERC=
    BATTERY_WARN_STATE= #required to save warning state
  fi
}

sample_mon_battery()
{
	if [ -n "$MON_BATTERY" ]; then :
    		# Get battery gauge.
    		REGB9H=$(i2cget -f -y 0 0x34 0xb9)    # Read AXP209 register B9H
    		MON_BATTERY_SAMPLE_PERC=$(($REGB9H))  # convert to decimal
		#echo $MON_BATTERY_SAMPLE_PERC"%"

    		# On CHIP, the battery detection (bit 5, reg 01H) does not work (stuck "on"
    		# even when battery is disconnected).  Also, when no battery connected,
    		# the battery discharge current varies wildly (probably a floating lead).  
    		# So assume the battery is NOT discharging when MicroUSB and/or CHG-IN
    		# are present (i.e. when chip is "powered").
    		REG00H=$(i2cget -f -y 0 0x34 0x00)    # Read AXP209 register 00H
    		PWR_BITS=$(( $REG00H & 0x50 ))        # ACIN usalbe and VBUS usable bits
		if [ $PWR_BITS -ne 0 ]; then :
			MON_BATTERY_SAMPLE_PWR=1
		else
			MON_BATTERY_SAMPLE_PWR=0
		fi

		BAT_ICHG_MSB=$(i2cget -y -f 0 0x34 0x7A)
		BAT_ICHG_LSB=$(i2cget -y -f 0 0x34 0x7B)
		#echo $BAT_ICHG_MSB $BAT_ICHG_LSB
		BAT_ICHG_BIN=$(( $(($BAT_ICHG_MSB << 4)) | $(($(($BAT_ICHG_LSB & 0x0F)) )) ))
		BAT_CHR_CUR=$(echo "($BAT_ICHG_BIN*0.5)"|bc)
		BAT_CHR_CUR=${BAT_CHR_CUR%%.*}

		POWER_OP_MODE=$(i2cget -y -f 0 0x34 0x01)
		#echo $POWER_OP_MODE

		CHARG_IND=$(($(($POWER_OP_MODE&0x40))/64))  # divide by 64 is like shifting rigth 6 times

  	fi
}

check_shut_battery()
{
  if [ -n "$MON_BATTERY" ]; then :
    if [ $MON_BATTERY_SAMPLE_PWR -eq 0 -a \
         $MON_BATTERY_SAMPLE_PERC -lt $MON_BATTERY ]; then :
      shutdown_now "battery($MON_BATTERY_SAMPLE_PERC)"
    fi
  fi
}

check_warn_battery()
{
	if [ -n "$MON_BATTERY" -a -n "$WARN_BATTERY" ]; then :
		# Check if already in temperature warning state.
		if [ -n "$BATTERY_WARN_STATE" ]; then :
			# To prevent rapid flapping between warn and non-warn, while
			# in battery warning state, require gauge rise 2% above
			# warning level to exit warning state (adds hysteresis).
			TEST_BATTERY=$(( $WARN_BATTERY + 2 ))
			if [ $MON_BATTERY_SAMPLE_PWR -eq 0 -a \
				$MON_BATTERY_SAMPLE_PERC -lt $TEST_BATTERY ]; then :
				# Battery still in warning was  Already in warning state.
				# blink power led
				invert_pwr_gpio
			else :
				# Battery out of warning.  Exit warning state.
				echo "Blink: battery warning resolved."
				BATTERY_WARN_STATE=
				if [ -n "$WARN_BATTERY_GPIO" ]; then :
					if [ $WARN_BATTERY_LED_STATUS -ne $WARN_BATTERY_DEFAULT_VALUE ]; then
						# flip LED to non - default, (default is off, so it should be on if fully charged)
						invert_pwr_gpio
					fi
				fi
			fi
		else :
			# Not in warning state, see if need to enter it.
			TEST_BATTERY=$(( $WARN_BATTERY ))
			if [ $MON_BATTERY_SAMPLE_PWR -eq 0 -a \
				$MON_BATTERY_SAMPLE_PERC -lt $TEST_BATTERY ]; then :
				# Battery entering warning state.
				echo "Blink: Warning: battery."
				BATTERY_WARN_STATE=1
				# blink power led
				invert_pwr_gpio
			else :
				# Battery not in warning.
			fi
		fi

		if [ -n "$CHR_LED_GPIO" ]; then :
			if [ $MON_BATTERY_SAMPLE_PWR -eq 1 ]; then :
				# power connected
				if [ $CHARG_IND -eq 1 ]; then :
					#charging, blink chr LED
					echo "charing bink chr led" $MON_BATTERY_SAMPLE_PERC
					invert_chr_gpio
				else :
					# fully charged, turn it ON (opposite of default (off))
					if [ $CHR_LED_STATUS -eq $CHR_LED_DEFAULT_VALUE ]; then :
						# flip LED to non - default, (default is off, so it should be on if fully charged)
						invert_chr_gpio
					fi
				fi
			else :
				# no power connected, led NOT in default mode, flip to default
				if [ $CHR_LED_STATUS -ne $CHR_LED_DEFAULT_VALUE ]; then :
					invert_chr_gpio
				fi
			fi
		fi
	fi
}





shutdown_now()
{
  echo "Shutdown, reason='$1'"
  shutdown -h now
}

#########################################################################
echo "blink: starting"
# Initialize everything
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
read_config

init_chr_gpio
init_mon_reset # reset button push
init_mon_battery # shutdown on battery init

# Write PID of running script to /tmp/blink.pid
echo $$ >/run/blink.pid
# Respond to control-c, kill, and service stop
trap "blink_stop" 1 2 3 15

while true; do :
	# check reset button
	sample_mon_reset # check status of reset button short press
	check_shut_reset # shutdown on reset button press
	
	# check battery state
	sample_mon_battery # returns MON_BATTERY_SAMPLE_PWR and MON_BATTERY_SAMPLE_PERC
	check_shut_battery #   shutdown when battery empty
	check_warn_battery #  blink gpio if battery about to be empty
	sleep 0.5
done
