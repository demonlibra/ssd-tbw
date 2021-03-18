#!/bin/bash

# Проверка наличия установленного пакета smartmontools
check=`whereis smartmontools`
if [ ! "${check#*:}" ]
	then
		echo -e '\E[1;31m'"smartmontools не установлен"
		tput sgr0
		echo "Выполните команду sudo apt install smartmontools"
		echo
		read -p "Нажмите ENTER чтобы завершить сценарий."
		exit
fi

# Предварительный ввод пароля
echo "Для выполнения команды smartctl подтребуются права root"
echo
sudo echo
clear

# Вывод списка всех накопителей
echo
echo "Обнаружены следующие накопители:"
echo
lsblk -d -o NAME,SIZE,MODEL,SERIAL
echo "------------------------------------------------------"

# Поиск накопителей SSD
echo
echo "Обнаружены следующие накопители SSD:"
echo
disks=`lsblk -d -n -o NAME`

# Перебираем диски
for disk in $disks
	do
		if [ `sudo smartctl /dev/"$disk" -i | grep -c -i "ssd\|solid.state\|nvme"` -ne 0 ]
			then lsblk -d -o NAME,SIZE,MODEL,SERIAL /dev/$disk
		fi
done
echo "------------------------------------------------------"

# Ввод индентификатора накопителя
echo
echo -n "Введите идентификатор накопителя из поля NAME: /dev/"
read dev
dev=$dev

if [[ $disks == *"$dev"* ]]
	then

		# Вывод информации о накопителе
		echo
		sudo smartctl /dev/"$dev" -i | grep -i "Device Model" | sed 's/Device Model:/Модель:              /g'
		sudo smartctl /dev/"$dev" -i | grep -i "Serial Number" | sed 's/Serial Number:/Серийный номер:       /g'
		sudo smartctl /dev/"$dev" -i | grep -i "User Capacity" | sed 's/User Capacity:/Объем:                /g'

		# Занятое место на разделах выбранного накопителя
		list_parts=`lsblk -l -p -n -o NAME /dev/$dev`								# Список разделов накопителя
		used=`df --total --block-size=G --output=used $list_parts | tail -n 1 | sed 's/G//g' | sed 's/ //g'`	# Суммарный занимаемый объем в Гбайтах
		size=`df --total --block-size=G --output=size $list_parts | tail -n 1 | sed 's/G//g' | sed 's/ //g'`	# Суммарный объем диска
		avail=`df --total --block-size=G --output=avail $list_parts | tail -n 1 | sed 's/G//g' | sed 's/ //g'`	# Свободный объем диска
		echo "Всего занято на разделах: $used Гбайт"

		# Размер сектора
		sector_size=`cat /sys/block/"$dev"/queue/hw_sector_size`
		echo "Размер сектора:           $sector_size байт"

		ATTRIBUTE241=`sudo smartctl /dev/"$dev" -A | grep "241 Total\|241 Host\|241 Lifetime"`
		ATTRIBUTE241_NAME=${ATTRIBUTE241#* }
		ATTRIBUTE241_NAME=${ATTRIBUTE241_NAME%% *}
		ATTRIBUTE241_VALUE=${ATTRIBUTE241##* }					# Значение - символы от последнего пробела справа
		
		if [ -n "$ATTRIBUTE241_VALUE" ]
			then
				echo "241 $ATTRIBUTE241_NAME:   $ATTRIBUTE241_VALUE"
				# Расчет записанных данных
				if [[ -n `echo $ATTRIBUTE241_NAME | grep "LBAs"` ]]
					then TBW=`echo "scale=3; $sector_size * $ATTRIBUTE241_VALUE / 1024 / 1024 / 1024 / 1024" | bc -l | sed 's/^\./0./'`
				elif [[ -n `echo $ATTRIBUTE241_NAME | grep "GiB\|GB"` ]]
					then TBW=`echo "scale=3; $ATTRIBUTE241_VALUE / 1024" | bc -l | sed 's/^\./0./'`
				elif [[ -n `echo $ATTRIBUTE241_NAME | grep "32MiB"` ]]
					then TBW=`echo "scale=3; $ATTRIBUTE241_VALUE * 32 / 1024 / 1024" | bc -l | sed 's/^\./0./'`
				fi
		fi
		
		if [ -z "$TBW" ]
			then
				echo
				echo -e '\E[1;31m'"Атрибут с объемом записанных данных не найден."
				tput sgr0
				echo "Откройте дополнительное окно терминала и выполните команду sudo smartctl -A /dev/$dev"
				echo -ne "Проанализируйте вывод smartmontools самостоятельно и введите общий записанный объема в терабайтах: "
				read test
				test=${test//,/.}
				re='^[0-9]+([.][0-9]+)?$'
				if [[ "$test" =~ $re ]]
					then
						TBW=$test
						TBWG=`echo "$TBW * 1024" | bc -l`
				else
					echo -e '\E[1;31m'"Введено некорректное значение."
					echo
					read -p "Нажмите ENTER чтобы завершить сценарий."
					exit
				fi
		fi
		
		if [ -n "$TBW" ]
			then
				echo
				echo -e '\E[1;34m'"Всего записано данных (TBW): $TBW ТБайт"; tput sgr0

				# Косвенная проверка данных параметра 241
				TBWG=`echo "$TBW * 1024" | bc -l`	# TBW в ГБайтах
				TBWG=${TBWG%%.*}

				if  [ "$used" -gt "$TBWG" ]
					then echo
						echo -e '\E[1;31m'"Вероятно данные TBW определены неверно."
						tput sgr0
						echo "Производитель заложил в параметр 241 только ему ведомые значения."
						echo "Занимаемое место ($used Гбайт) больше вычисленного значения TBW ($TBWG Гбайт)."

						echo
						echo -n "Введите Y для выполнения тестовой записи или проанализируйте вывод smartmontools самостоятельно и введите общий записанный объем в Тб:"
						read test
						re='^[0-9]+$'
						if [[ "$test" =~ $re ]]
							then
								TBW=$test
								TBWG=`echo "$TBW * 1024" | bc -l`
						elif [ "${test,,}" = "y" ]
							then
								echo -n "Введите полный путь к файлу на разделе SSD для тестовой записи (по умолчанию ssd_test): "
								read path_ssd
								if [ -z $path_ssd ]; then path_ssd=ssd_test; fi

								echo -n "Введите объем записываемых данных в Мб (по умолчанию 2048Мб или 2Гб): "
								read capacity
								if [ -z $capacity ]; then capacity=2048; fi

								echo "------------------------------------------------------"

								#dd if=/dev/urandom of="$path_ssd" bs=1M count=$capacity status=progress
								sync
								
								ATTRIBUTE241=`sudo smartctl /dev/"$dev" -A | grep "241 Total\|241 Host\|241 Lifetime"`
								ATTRIBUTE241_VALUE_before=${ATTRIBUTE241##* }
								
								dd if=/dev/urandom of="$path_ssd" bs=1M count=$capacity status=progress conv=excl
								sync

								ATTRIBUTE241=`sudo smartctl /dev/"$dev" -A | grep "241 Total\|241 Host\|241 Lifetime"`
								ATTRIBUTE241_VALUE_after=${ATTRIBUTE241##* }
								
								echo
								echo "241 до записи = $ATTRIBUTE241_VALUE_before"
								echo "241 после записи = $ATTRIBUTE241_VALUE_after"

								difference=$(($ATTRIBUTE241_VALUE_after - $ATTRIBUTE241_VALUE_before))
								echo "Разница = $difference"
								
								if [ $difference -gt 0 ]
									then
										ratio=$(($capacity * 1024 * 1024 / $difference))
										echo "Коэффициент = $ratio"

										TBW=`echo "scale=3; $ATTRIBUTE241_VALUE_after * $ratio / 1024 / 1024 / 1024 / 1024" | bc -l | sed 's/^\./0./'`
										TBWG=`echo "$TBW * 1024" | bc -l`
										TBWG=${TBWG%%.*}

										echo
										echo -e '\E[1;34m'"Расчитанное значение TBW после тестовой записи: $TBW ТБайт"
										tput sgr0
										rm $path_ssd
										echo "------------------------------------------------------"
									else
										echo -e '\E[1;31m'"Параметр 241 не изменился. Определить объем записанных данных не удалось."
										tput sgr0
										echo "Вы можете попробовать указать объем тестовой записи на порядок больше."
										echo
										read -p "Нажмите ENTER чтобы завершить сценарий."
										exit
								fi
						fi
				fi

			else
				echo
				echo -e '\E[1;31m'"Вывод smartctl не содержит данных для определения записанных данных"
				echo "Возможно вы указали не SSD накопитель."
				tput sgr0
				echo
				read -p "Нажмите ENTER чтобы завершить сценарий."
				exit
		fi


		# Количество отработанных часов
		Power_On_Hours=`sudo smartctl /dev/"$dev" -A | grep -i "Power.On.Hours"`
		Power_On_Hours=${Power_On_Hours##* }
		echo
		echo "9 Power_On_Hours: $Power_On_Hours"
		Power_On_Hours=${Power_On_Hours%%h*}
		Power_On_Days=`echo "scale=0; $Power_On_Hours / 24 " | bc -l | sed 's/^\./0./'`
		Power_On_Years=`echo "scale=2; $Power_On_Hours / 24 / 365" | bc -l | sed 's/^\./0./'`
		echo -e '\E[1;34m'"Всего отработано: $Power_On_Hours часов = $Power_On_Days дней = $Power_On_Years лет"; tput sgr0

		# Ввод даты установки накопителя
		echo
		echo -n "Введите дату установки накопителя (в формате год-месяц-число): "
		read start_use

		# Статистика использования накопителя от даты установки
		if [ -n "$start_use" ]
			then
				today_seconds=`date '+%s'`
				start_use=${start_use//[^0-9]/}								# Оставляем в дате только цифры
				start_use_seconds=`date -d "$start_use" '+%s'`
				if [ $? = 0 ] && [ $today_seconds -gt $start_use_seconds ]
					then
						days_use=$(( ($today_seconds - $start_use_seconds) / (24 * 3600) ))
						years_use=`echo "scale=1; ($days_use / 365)" | bc -l | sed 's/^\./0./'`
						#echo $days_use
						#$echo $years_use
						percent_use=$((100 * $Power_On_Days / $days_use))
						
						echo
						echo "Накопитель использовался ${percent_use}% времени с момента установки в течении $years_use (лет)"
						
						if [ -n "$TBWG" ]
							then
								TBWG_day=`echo "scale=1; ($TBWG / $days_use)" | bc -l | sed 's/^\./0./'`
								TBW_year=`echo "scale=1; (365 * $TBW / $days_use)" | bc -l | sed 's/^\./0./'`
								echo "Средний объем записываемых данных: ${TBWG_day} ГБайт в день или ${TBW_year} Тбайт в год"
								
								echo
								echo -n "Введите гарантированный производителем объем записываемых данных (Тбайт): "
								read garanty_TBW
								garanty_TBW=${garanty_TBW%%,*}	#Убираем дробную часть, если ввели запятую 
								garanty_TBW=${garanty_TBW%%.*}	#Убираем дробную часть, если ввели точку
								
								if [ -n "$garanty_TBW" ]
									then
										resource=`echo "scale=1; ($TBWG / 1024 * 100 / $garanty_TBW)" | bc -l | sed 's/^\./0./'`
										resource_year=`echo "scale=1; ($resource / $years_use)" | bc -l | sed 's/^\./0./'`
										echo
										resource_round=${resource%%.*}
										if (( $resource_round < 30 ))
											then echo -e '\E[1;32m'"Израсходованный ресурс: ${resource}% за ${years_use} лет (${resource_year}% в год)"; tput sgr0 
										elif (( $resource_round < 50 ))
											then echo -e '\E[1;33m'"Израсходованный ресурс: ${resource}% за ${years_use} лет (${resource_year}% в год)"; tput sgr0
											else echo -e '\E[1;31m'"Израсходованный ресурс: ${resource}% за ${years_use} лет (${resource_year}% в год)"; tput sgr0
										fi
										echo "Теоретический срок эксплуатации (лет): "$(($garanty_TBW * 1024 / $TBWG * $days_use / 365))
										echo "Теоретический срок эксплуатации (лет) с учетом свободного места: "$(($garanty_TBW * 1024 / $TBWG * $days_use / 365*$avail/$size))
										#echo
								fi

						fi
						
					else
						echo -e '\E[1;31m'"Дата введена некорректно"
						tput sgr0
						echo
						read -p "Нажмите ENTER чтобы завершить сценарий."
						exit
				fi
		fi

		
	else
		echo -e '\E[1;31m'"Накопитель с идентификатором \"$dev\" не обнаружен."
		tput sgr0
		echo "Проверьте вводимые данные и повторите попытку."
		echo
		read -p "Нажмите ENTER чтобы завершить сценарий."
		exit
fi

date_now=$(date +%F"_"%H-%M-%S)
#echo "Дата запуска сценария: "$date_now

# Проверка наличия установленного пакета gnome-screenshot
check=`whereis gnome-screenshot`
if [ "${check#*:}" ]
	then
		echo
		echo -n "Разверните окно терминала и введите Y чтобы сохранить снимок в файл: "
		read screenshot

		if [ "${screenshot,,}" = "y" ]
			then gnome-screenshot -w -B -f "ssd-tbw_${date_now}.png"
		fi
fi