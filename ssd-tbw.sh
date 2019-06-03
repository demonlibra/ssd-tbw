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

echo
echo "Всего записано данных: $TBW ТБайт"

# Косвенная проверка данных параметра 241
list_parts=`lsblk -l -p -n -o NAME /dev/$dev`															# Список разделов устройства
used=`df --total --block-size=G --output=used $list_parts | tail -n 1 | sed 's/G//g' | sed 's/ //g'`	# Суммарный занимаемый объем в Гбайтах
echo "Всего занято на разделах диска: $used Гбайт"
TBWG=`echo "$TBW * 1024" | bc -l`
TBWG=${TBWG%%.*}

if [[ "$used" -gt "$TBWG" ]]
	then echo
		echo "Вероятно данные TBW определены неверно."
		echo "Занимаемое место на диске ($used Гбайт) больше определенного значения TBW ($TBWG Гбайт)."
fi

# Количество отработанных часов
Power_On_Hours=`sudo smartctl /dev/"$dev" --all | grep "Power_On_Hours"`
Power_On_Hours=${Power_On_Hours##* }
echo
echo "9 Power_On_Hours: $Power_On_Hours"
Power_On_Hours=${Power_On_Hours%%h*}
Power_On_Years=`echo "scale=2; $Power_On_Hours / 24 / 365" | bc -l | sed 's/^\./0./'`

echo "Всего отработано: $Power_On_Hours часов ($Power_On_Years лет)"
echo

read -p "Нажмите ENTER чтобы закрыть окно"
