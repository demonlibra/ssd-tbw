#!/bin/bash

# Вывод списка всех дисков
echo
echo "Обнаружены следующие диски:"
echo
lsblk -d -o NAME,SIZE,MODEL,SERIAL
echo "------------------------------------------------------"

# Поиск дисков SSD
echo
echo "Обнаружены следующие диски SSD:"
echo
disks=`lsblk -d -n -o NAME`
for disk in $disks
	do
		if [ `sudo smartctl /dev/"$disk" --all | grep -c "SSD"` -ne 0 ]
			then lsblk -d -o NAME,SIZE,MODEL,SERIAL /dev/$disk
		fi
done
echo "------------------------------------------------------"

# Ввод индентификатора диска
echo
echo -n "Введите идентификатор диска /dev/"
read dev

if [[ $disks == *"$dev"* ]]
	then

		# Вывод информации о диске
		echo
		sudo smartctl /dev/"$dev" --all | grep "Device Model" | sed 's/"Device Model"/"Модель диска"/g'
		sudo smartctl /dev/"$dev" --all | grep "Serial Number" | sed 's/"Serial Number"/"Серийный номер"/g'
		sudo smartctl /dev/"$dev" --all | grep "User Capacity" | sed 's/"User Capacity"/"Объем диска"/g'

		# Всего записано блоков - 241 Total_LBAs_Written
		Total_LBAs_Written=`sudo smartctl /dev/"$dev" --all | grep "Total_LBAs_Written"`
		Total_LBAs_Written=${Total_LBAs_Written##* }
		echo
		echo "241 Total_LBAs_Written: $Total_LBAs_Written"

		# Всего записано Gib - 241 Lifetime_Writes_GiB
		Lifetime_Writes_GiB=`sudo smartctl /dev/"$dev" --all | grep "Lifetime_Writes_GiB"`
		Lifetime_Writes_GiB=${Lifetime_Writes_GiB##* }
		echo "241 Lifetime_Writes_GiB: $Lifetime_Writes_GiB"

		# Всего записано блоков по 32MiB - 241 Host_Writes_32MiB
		Host_Writes_32MiB=`sudo smartctl /dev/"$dev" --all | grep "Host_Writes_32MiB"`
		Host_Writes_32MiB=${Host_Writes_32MiB##* }
		echo "241 Host_Writes_32MiB: $Host_Writes_32MiB"


		# Размер сектора
		sector_size=`cat /sys/block/"$dev"/queue/hw_sector_size`
		echo
		echo "Sector Size: $sector_size"

		# Расчет записанных данных
		if [ -n "$Total_LBAs_Written" ]
			then TBW=`echo "scale=3; $sector_size * $Total_LBAs_Written / 1024 / 1024 / 1024 / 1024" | bc -l | sed 's/^\./0./'`
		elif [ -n "$Lifetime_Writes_GiB" ]
			then TBW=`echo "scale=3; $Lifetime_Writes_GiB / 1024" | bc -l | sed 's/^\./0./'`
		elif [ -n "$Host_Writes_32MiB" ]
			then TBW=`echo "scale=3; $Host_Writes_32MiB * 32 / 1024 / 1024" | bc -l | sed 's/^\./0./'`
		fi

		if [ -n "$TBW" ]
			then
				echo
				echo -e '\E[1;34m'"Всего записано данных: $TBW ТБайт"; tput sgr0

				# Косвенная проверка данных параметра 241
				list_parts=`lsblk -l -p -n -o NAME /dev/$dev`															# Список разделов устройства
				used=`df --total --block-size=G --output=used $list_parts | tail -n 1 | sed 's/G//g' | sed 's/ //g'`	# Суммарный занимаемый объем в Гбайтах
				echo "Всего занято на разделах диска: $used Гбайт"
				TBWG=`echo "$TBW * 1024" | bc -l`																		#TBW в ГБайтах
				TBWG=${TBWG%%.*}

				if  [ "$used" -gt "$TBWG" ]
					then echo
						echo "Вероятно данные TBW определены неверно."
						echo "Производитель заложил в параметр 241 только ему ведомые значения."
						echo "Занимаемое место на диске ($used Гбайт) больше определенного значения TBW ($TBWG Гбайт)."

						echo
						echo -n "Введите Y для выполнения тестовой записи: "
						read test
						if [ "${test,,}" = "y" ]
							then
								echo -n "Введите полный путь к файлу на SSD для тестовой записи (по умолчанию ssd_test): "
								read path_ssd
								if [ -z $path_ssd ]; then path_ssd=ssd_test; fi

								echo -n "Введите объем данных в Мб (по умолчанию 100): "
								read capacity
								if [ -z $capacity ]; then capacity=100; fi

								echo "------------------------------------------------------"

								#dd if=/dev/urandom of="$path_ssd" bs=1M count=$capacity status=progress
								sync

								Total_LBAs_Written=`sudo smartctl /dev/"$dev" --all | grep "Total_LBAs_Written"`
								Total_LBAs_Written=${Total_LBAs_Written##* }
								echo
								echo "241 до записи = $Total_LBAs_Written"
								echo

								dd if=/dev/urandom of="$path_ssd" bs=1M count=$capacity status=progress
								sync
								echo

								Total_LBAs_Written_check=`sudo smartctl /dev/"$dev" --all | grep "Total_LBAs_Written"`
								Total_LBAs_Written_check=${Total_LBAs_Written_check##* }
								echo "241 после записи = $Total_LBAs_Written_check"

								difference=$(($Total_LBAs_Written_check - $Total_LBAs_Written))
								echo "Разница = $difference"
								ratio=$(($capacity * 1024 * 1024 / $difference))
								echo "Коэффициент = $ratio"
								TBW=`echo "scale=3; $Total_LBAs_Written * $ratio / 1024 / 1024 / 1024 / 1024" | bc -l | sed 's/^\./0./'`
								TBWG=`echo "$TBW * 1024" | bc -l`
								TBWG=${TBWG%%.*}

								echo
								echo -e '\E[1;34m'"Расчитанное значение TBW после тестовой записи: $TBW ТБайт"; tput sgr0
								rm $path_ssd
								echo "------------------------------------------------------"
						fi
				fi

			else
				echo
				echo -e '\E[1;31m'"Вывод smartctl не содержит данных для определения записанных данных"; echo "Возможно вы указали не SSD диск."; tput sgr0
		fi


		# Количество отработанных часов
		Power_On_Hours=`sudo smartctl /dev/"$dev" --all | grep "Power_On_Hours"`
		Power_On_Hours=${Power_On_Hours##* }
		echo
		echo "9 Power_On_Hours: $Power_On_Hours"
		Power_On_Hours=${Power_On_Hours%%h*}
		Power_On_Days=`echo "scale=0; $Power_On_Hours / 24 " | bc -l | sed 's/^\./0./'`
		Power_On_Years=`echo "scale=2; $Power_On_Hours / 24 / 365" | bc -l | sed 's/^\./0./'`
		echo -e '\E[1;34m'"Всего отработано: $Power_On_Hours часов = $Power_On_Days дней = $Power_On_Years лет"; tput sgr0

		# Ввод даты установки диска
		echo
		echo -n "Введите дату начала использования диска (пример формата 2018-01-01 или 20180101 или 180101 или 18-01-01): "
		read start_use
		
		# Статистика использования диска от даты установки
		if [ -n "$start_use" ]
			then
				today_seconds=`date '+%s'`
				start_use_seconds=`date -d "$start_use" '+%s'`
				if [ $? = 0 ] && [ $today_seconds -gt $start_use_seconds ]
					then
						days_use=$(( ($today_seconds - $start_use_seconds) / (24 * 3600) ))
						#echo $days_use
						percent_use=$((100 * $Power_On_Days / $days_use))
						echo
						echo "Диск находился в работе "$percent_use"% от общего срока службы"
						if [ -n "$TBWG" ]
							then echo "Средний объем записываемых данных: "$(($TBWG / $days_use))" ГБайт в день"
						fi
					else echo -e '\E[1;31m'"Дата введена не корректно"; tput sgr0
				fi
		fi

		
	else echo -e '\E[1;31m'"Диск \"$dev\" не обнаружен. Проверьте вводимые данные"; tput sgr0
fi

echo
read -p "Нажмите ENTER чтобы закрыть окно"
