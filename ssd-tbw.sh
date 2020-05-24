#!/bin/bash
# Предварительный ввод пароля
echo "Для выполнения команды smartctl подтребуются права root"
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

# Проверка наличия установленного пакета smartmontools
if [[ `dpkg -l| grep smartmontools` = "" ]]
	then
		echo "smartmontools не установлен"
		echo "Выполните команду sudo apt install smartmontools"
		echo
		read -p "Нажмите ENTER чтобы закрыть окно"
		exit
fi

# Перебираем диски
for disk in $disks
	do
		if [ `sudo smartctl /dev/"$disk" -i | grep -c -i "SSD"` -ne 0 ]
			then lsblk -d -o NAME,SIZE,MODEL,SERIAL /dev/$disk
		fi
done
echo "------------------------------------------------------"

# Ввод индентификатора накопителя
echo
echo -n "Введите идентификатор накопителя /dev/"
read dev

if [[ $disks == *"$dev"* ]]
	then

		# Вывод информации о накопителе
		echo
		sudo smartctl /dev/"$dev" -i | grep "Device Model" | sed 's/Device Model:/Модель:              /g'
		sudo smartctl /dev/"$dev" -i | grep "Serial Number" | sed 's/Serial Number:/Серийный номер:       /g'
		sudo smartctl /dev/"$dev" -i | grep "User Capacity" | sed 's/User Capacity:/Объем:                /g'

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
		echo "241 $ATTRIBUTE241_NAME:   $ATTRIBUTE241_VALUE"
		
		# Расчет записанных данных
		if [[ -n `echo $ATTRIBUTE241_NAME | grep "LBAs"` ]]
			then TBW=`echo "scale=3; $sector_size * $ATTRIBUTE241_VALUE / 1024 / 1024 / 1024 / 1024" | bc -l | sed 's/^\./0./'`
		elif [[ -n `echo $ATTRIBUTE241_NAME | grep "GiB\|GB"` ]]
			then TBW=`echo "scale=3; $ATTRIBUTE241_VALUE / 1024" | bc -l | sed 's/^\./0./'`
		elif [[ -n `echo $ATTRIBUTE241_NAME | grep "32MiB"` ]]
			then TBW=`echo "scale=3; $ATTRIBUTE241_VALUE * 32 / 1024 / 1024" | bc -l | sed 's/^\./0./'`
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
						echo "Вероятно данные TBW определены неверно."
						echo "Производитель заложил в параметр 241 только ему ведомые значения."
						echo "Занимаемое место ($used Гбайт) больше вычисленного значения TBW ($TBWG Гбайт)."

						echo
						echo -n "Введите Y для выполнения тестовой записи: "
						read test
						if [ "${test,,}" = "y" ]
							then
								echo -n "Введите полный путь к файлу на разделе SSD для тестовой записи (по умолчанию ssd_test): "
								read path_ssd
								if [ -z $path_ssd ]; then path_ssd=ssd_test; fi

								echo -n "Введите объем данных в Мб (по умолчанию 100): "
								read capacity
								if [ -z $capacity ]; then capacity=100; fi

								echo "------------------------------------------------------"

								#dd if=/dev/urandom of="$path_ssd" bs=1M count=$capacity status=progress
								sync
								
								ATTRIBUTE241=`sudo smartctl /dev/"$dev" -A | grep "241 Total\|241 Host\|241 Lifetime"`
								ATTRIBUTE241_VALUE_before=${ATTRIBUTE241##* }
								
								dd if=/dev/urandom of="$path_ssd" bs=1M count=$capacity status=progress
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
										echo -e '\E[1;34m'"Расчитанное значение TBW после тестовой записи: $TBW ТБайт"; tput sgr0
										rm $path_ssd
										echo "------------------------------------------------------"
									else
										echo "Параметр 241 не изменился. Определить объем записанных данных не удалось."
										echo "Вы можете попробовать указать объем тестовой записи на порядок больше, например 1024 Мб."
								fi
						fi
				fi

			else
				echo
				echo -e '\E[1;31m'"Вывод smartctl не содержит данных для определения записанных данных"; echo "Возможно вы указали не SSD накопитель."; tput sgr0
		fi


		# Количество отработанных часов
		Power_On_Hours=`sudo smartctl /dev/"$dev" -A | grep "Power_On_Hours"`
		Power_On_Hours=${Power_On_Hours##* }
		echo
		echo "9 Power_On_Hours: $Power_On_Hours"
		Power_On_Hours=${Power_On_Hours%%h*}
		Power_On_Days=`echo "scale=0; $Power_On_Hours / 24 " | bc -l | sed 's/^\./0./'`
		Power_On_Years=`echo "scale=2; $Power_On_Hours / 24 / 365" | bc -l | sed 's/^\./0./'`
		echo -e '\E[1;34m'"Всего отработано: $Power_On_Hours часов = $Power_On_Days дней = $Power_On_Years лет"; tput sgr0

		# Ввод даты установки накопителя
		echo
		echo -n "Введите дату начала использования накопителя в формате год-месяц-число: "
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
						#echo $days_use
						percent_use=$((100 * $Power_On_Days / $days_use))
						
						echo
						echo "Накопитель находился в работе "$percent_use"% времени с момента начала использования"
						
						if [ -n "$TBWG" ]
							then
								echo "Средний объем записываемых данных (ГБайт в день): "$(($TBWG / $days_use))
								
								echo
								echo -n "Введите гарантированный производителем объем записываемых данных (Тбайт): "
								read garanty_TBW
								
								if [ -n "$garanty_TBW" ]
									then
										resource=`echo "scale=1; ($TBWG / 1024 * 100 / $garanty_TBW)" | bc -l | sed 's/^\./0./'`
										echo
										resource_round=${resource%%.*}
										if (( $resource_round < 30 ))
											then echo -e '\E[1;32m'"Израсходованный ресурс: $resource%"; tput sgr0 
										elif (( $resource_round < 50 ))
											then echo -e '\E[1;33m'"Израсходованный ресурс: $resource%"; tput sgr0
										else echo -e '\E[1;31m'"Израсходованный ресурс: $resource%"; tput sgr0
										fi
										echo "Теоретический срок эксплуатации (лет): "$(($garanty_TBW * 1024 / $TBWG * $days_use / 365))
										echo "Теоретический срок эксплуатации (лет) с учетом свободного места: "$(($garanty_TBW * 1024 / $TBWG * $days_use / 365*$avail/$size))
										echo
										echo "Дата запуска сценария: "$(date +%F" "%H-%M-%S)
								fi

						fi
						
					else echo -e '\E[1;31m'"Дата введена некорректно"; tput sgr0
				fi
		fi

		
	else echo -e '\E[1;31m'"Накопитель \"$dev\" не обнаружен. Проверьте вводимые данные"; tput sgr0
fi

echo
read -p "Нажмите ENTER чтобы закрыть окно"
