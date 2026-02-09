import sys, time, math, random, csv, serial
import numpy as np
import tkinter as tk
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
from matplotlib.colors import LinearSegmentedColormap
from matplotlib.animation import FuncAnimation
from itertools import count

timeS_data, tempC_data, tempF_data, state_data = 0, 0, 0, ''
fieldnames = ['timeS_data', 'tempC_data', 'tempF_data', 'state_data']
timeS_x, tempC_y, tempF_y, state_c = [], [], [], []
MODES = [
    ('Inactive', 0),
    ('Ramp to Soak', 1),
    ('Preheat/Soak', 2),
    ('Ramp to Peak', 3),
    ('Reflow', 4),
    ('Cooling', 5)
]

COLORS = [
    "#1C0076", # Deep Indigo
    "#0000FF", # Pure Blue
    "#00FFE1", # Cyan
    "#F0F0F0", # Soft White
    "#FFFF00", # Yellow
    "#FFA500", # Orange
    "#FF0000", # Red
    "#490000"  # Deep Maroon
    ]
thermal_map = LinearSegmentedColormap.from_list('thermal', COLORS, N=256)

#ser = serial.Serial(port='COM3', baudrate=115200, parity=serial.PARITY_NONE, stopbits=serial.STOPBITS_TWO, bytesize=serial.EIGHTBITS)
#ser.isOpen()

plt.xkcd()
plt.rcParams['font.family'] = 'xkcd script'
index = count()

fig, (axC, axF) = plt.subplots(2, 1)
plt.subplots_adjust(hspace=0.25)

lineC, = axC.plot(timeS_x, tempC_y, color="#000000", linestyle='solid', label='Celsius', lw=3)
lineF, = axF.plot(timeS_x, tempF_y, color='#000000', linestyle='solid', label='Fahrenheit', lw=3)

axC.set_title('Live Temperature Monitor')
axC.set_ylabel('Celsius')
axF.set_ylabel('Fahrenheit')
axF.set_xlabel('Time (s)')

axC.grid(True)
axF.grid(True)

def get_thermal_hex(temp):
    # Maps from 25 - 250 > 0.0 - 1.0
    norm = (temp-25)/(250-25)
    norm = max(0, min(norm, 1.0))

    rgba = thermal_map(norm)
    return mcolors.to_hex(rgba)

def animate(_):
    global timeS_data, tempC_data, tempF_data, state_data

    #while ser.in_waiting > 0:
    try:
        #data = ser.readline().decode('utf-8').strip()
        #split_data = data.split(',')

        frequency = 0.05 
        amplitude = (250 - 25) / 2
        midpoint = 25 + amplitude

        timeS_data = 0.5*next(index)
        tempC_data = midpoint + amplitude * math.sin(frequency * timeS_data) #float(split_data[0])
        tempF_data = 1.8*tempC_data+32
        state_data = random.choice([m[0] for m in MODES]) #split_data[1]

        timeS_x.append(timeS_data)
        tempC_y.append(tempC_data)
        tempF_y.append(tempF_data)
        state_c.append(state_data)
        
        lineC.set_data(timeS_x, tempC_y)
        lineF.set_data(timeS_x, tempF_y)

        if len(timeS_x) > 1:
            current_hex = get_thermal_hex(tempC_data)
            axC.fill_between(timeS_x[-2:], tempC_y[-2:], color=current_hex, alpha=1)
            axF.fill_between(timeS_x[-2:], tempF_y[-2:], color=current_hex, alpha=1)

        maxC_t = max(tempC_y)
        minC_t = min(tempC_y)
        axC.legend([f'READING: {tempC_data:.2f}$^o$C\nMAX: {maxC_t:.2f}$^o$C\nMIN: {minC_t:.2f}$^o$C'], loc='upper left', handlelength=0, handletextpad=0)
        maxF_t = max(tempF_y)
        minF_t = min(tempF_y)
        axF.legend([f'READING: {tempF_data:.2f}$^o$F\nMAX: {maxF_t:.2f}$^o$F\nMIN: {minF_t:.2f}$^o$F'], loc='upper left', handlelength=0, handletextpad=0)
        
        axC.relim()
        axC.autoscale_view()
        axF.relim()
        axF.autoscale_view()

    except Exception as e:
        print(f'Error: {e}')

    return lineC, lineF

ani = FuncAnimation(plt.gcf(), animate, interval=500, blit=False, cache_frame_data=False)
plt.show()

with open('serialdata.csv', 'w') as csv_file:
    csv_writer = csv.DictWriter(csv_file, fieldnames=fieldnames, delimiter=',')

    csv_writer.writeheader()
    for t, c, f, s in zip(timeS_x, tempC_y, tempF_y, state_c, strict=False):
        csv_writer.writerow({
            'timeS_data': t, 'tempC_data': c,
            'tempF_data': f, 'state_data': s})

fig.savefig('reflowOvenPlot.png', dpi=300)