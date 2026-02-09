# Standard Library
import sys, time, math, random, csv, serial, requests, json, ctypes, smtplib
from itertools import count
from email.message import EmailMessage

# Data and Plotting
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
from matplotlib.collections import PolyCollection
from matplotlib.colors import LinearSegmentedColormap
from matplotlib.animation import FuncAnimation

# GUI
from tkinter import *
from tkinter import font as tkfont
from tkinter import messagebox
from PIL import ImageTk, Image

# TERMINAL REDIRECT CLASS

class TextRedirector:
    def __init__(self, widget):
        self.widget = widget
        
    def write(self, text):
        self.widget.config(state='normal')
        self.widget.insert('1.0', text)  # Insert at top (newest first)
        self.widget.config(state='disabled')
        self.widget.see('1.0')  # Auto-scroll to top
        
    def flush(self):
        pass  # Required for file-like object

# APPLICATION SETUP

# create application
ctypes.windll.shcore.SetProcessDpiAwareness(1) # Use actual screen instead of scaled
root = Tk()
root.resizable(False, False)
root.iconbitmap('gui/litovenicon.ico')
root.title('Reflow Oven GUI')
screen_width = root.winfo_screenwidth()
screen_height = root.winfo_screenheight()
root.geometry(f'{screen_width}x{screen_height}')
default_font = tkfont.nametofont('TkDefaultFont')
default_font.configure(family='xkcd script', size=15)
root.option_add('*Font', default_font)

# background wallpaper
image = Image.open('gui/crumpledpaper_bg.jpg')
bg_img = ImageTk.PhotoImage(image.resize((screen_width, screen_height), Image.Resampling.LANCZOS))
bg_label = Label(root, image=bg_img)
bg_label.place(x=0, y=0, relwidth=1, relheight=1)

# create grid layout
'''
GRAPH                 | STATUS INDICATOR
,                     -------------------------------
GRAPH                 | OVENAI
-----------------------------------------------------
EXPORT | EMAIL | PORT | TERMINAL
'''
# splitting up into rows and columns
root.grid_rowconfigure((0,1,2), weight=1, uniform='a')
root.grid_columnconfigure((0,1), weight=1, uniform='a')

# create frame for graphs
graph_frame = LabelFrame(root, text='Real Time Plotter', padx=5, pady=5)
graph_frame.grid(row=0, column=0, padx=20, pady=20, sticky='nsew', columnspan=1, rowspan=2)
graph_frame.grid_rowconfigure(0, weight=1)
graph_frame.grid_columnconfigure(0, weight=1)

# create frame for settings (row2-column0 to be sub-divided)
settings_frame = LabelFrame(root, text='Configure Settings', padx=5, pady=5)
settings_frame.grid(row=2, column=0, padx=20, pady=20, sticky='nsew', columnspan=1, rowspan=1)
settings_frame.grid_rowconfigure(0, weight=1)
settings_frame.grid_columnconfigure(0, weight=1)

# create subframes within settings frame
settings_frame.grid_columnconfigure(0, weight=1, uniform='a') # exports
settings_frame.grid_columnconfigure(1, weight=2, uniform='a') # email
settings_frame.grid_columnconfigure(2, weight=1, uniform='a') # serial
# create frame for exports
exports_frame = LabelFrame(settings_frame, text='Forward Files to Email', padx=5, pady=5)
exports_frame.grid(row=0, column=0, padx=5, pady=5, sticky='nsew', columnspan=1, rowspan=1)
exports_frame.grid_rowconfigure((0,1), weight=1)
exports_frame.grid_columnconfigure(0, weight=1)
# create frame for email
email_frame = LabelFrame(settings_frame, text='Enter Email for Notifications and Exports', padx=5, pady=5)
email_frame.grid(row=0, column=1, padx=5, pady=5, sticky='nsew', columnspan=1, rowspan=1)
email_frame.grid_rowconfigure((0,1), weight=1, uniform='a')
email_frame.grid_columnconfigure(0, weight=1)
# create frame for serial
serial_frame = LabelFrame(settings_frame, text='Serial Communication', padx=5, pady=5)
serial_frame.grid(row=0, column=2, padx=5, pady=5, sticky='nsew', columnspan=1, rowspan=1)
serial_frame.grid_rowconfigure((0,1), weight=1)
serial_frame.grid_columnconfigure(0, weight=1)

#create frame for status
status_frame = LabelFrame(root, text='Status Indicator', padx=5, pady=5)
status_frame.grid(row=0, column=1, padx=20, pady=20, sticky='nsew', columnspan=1, rowspan=1)

#create frame for ovenai
ovenai_frame = LabelFrame(root, text='OVEN AI', padx=5, pady=5)
ovenai_frame.grid(row=1, column=1, padx=20, pady=20, sticky='nsew', columnspan=1, rowspan=1)
ovenai_frame.grid_rowconfigure(0, weight=1)  # chat history takes most space
ovenai_frame.grid_rowconfigure(1, weight=0)  # input row stays small
ovenai_frame.grid_columnconfigure((0,1), weight=1)
# create input frame for the most recent message ai/user
input_frame = Frame(ovenai_frame)
input_frame.grid(row=1, column=0, columnspan=2, sticky='ew', padx=5, pady=5)
input_frame.grid_columnconfigure(0, weight=1)
input_frame.grid_columnconfigure(1, weight=1)

#create frame for terminal
terminal_frame = LabelFrame(root, text='Terminal Output', padx=5, pady=5)
terminal_frame.grid(row=2, column=1, padx=20, pady=20, sticky='nsew', columnspan=1, rowspan=1)
terminal_frame.grid_rowconfigure(0, weight=1)
terminal_frame.grid_columnconfigure(0, weight=1)

# GLOBAL VARIABLES

# initializing lists for data sampling
timeS_data, tempC_data, tempF_data, state_data = 0, 0, 0, ''
fieldnames = ['timeS_data', 'tempC_data', 'tempF_data', 'state_data']
timeS_x, tempC_y, tempF_y, state_c = [], [], [], []
poly_verts_C, poly_verts_F, poly_colors, poly_C, poly_F = [], [], [], None, None

# system settings and modes
PORTS = ['COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6']
DATA = ['Recieve', 'Transmit']
MODES = [
    ('Inactive', 0),
    ('Ramp to Soak', 1),
    ('Preheat/Soak', 2),
    ('Ramp to Peak', 3),
    ('Reflow', 4),
    ('Cooling', 5)
]

# graph fill colours
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

# INPUT FUNCTIONS

# save email at the return key
def save_email(event=None):
    global user_email
    user_email = email_tb.get()
    # creates a label below when email is saved
    emailLabel = Label(email_frame, text=f'Email Saved: {user_email}')
    emailLabel.grid(row=1, column=0, sticky='w')

# save last user input at the return key
def get_last_input(event=None):
    global last_input
    last_input = input_tb.get()
    chat_history.config(state='normal')
    chat_history.insert('1.0', f'USER: {last_input}\n\n')
    chat_history.config(state='disabled')
    input_tb.delete(0, END) # deletes current input
    get_ai_output(last_input)

def get_ai_output(user_input):
    global ai_output
    ai_output = f'processing... {user_input}'
    chat_history.config(state='normal')
    chat_history.insert('1.0', f"OVEN AI: {ai_output}\n")
    chat_history.config(state='disabled')
    ai_current_output.config(state='normal')
    ai_current_output.delete(0, END)
    ai_current_output.insert(0, ai_output)
    ai_current_output.config(state='readonly')
    # CALL OVEN API
    # try:
    #     api_request = requests.get('openaikeyhere')
    #     api = json.loads(api_request.content)
    # except Exception as e:
    #     api = e
    #ai_output = ...
    pass

# update mode from serial
def update_mode(new_value):
    mode_var.set(new_value)

# check if user tried to select 'transmit' while AI is empty
def validate_mode_change(*args):
    if data_var.get() == DATA[1] and ai_output is None:
        data_var.set(DATA[0]) # force it back to recieve
        root.update_idletasks() # update the button immediately
        messagebox.showerror('Reflow Oven GUI', 'Cannot Transmit: No AI output generated yet')

# export csv popup
def pop_csv():
    if user_email == None:
        messagebox.showerror('Reflow Oven GUI', f'Please confirm your email to export CSV')
    else:
        try:
            with open('serialdata.csv', 'w') as csv_file:
                csv_writer = csv.DictWriter(csv_file, fieldnames=fieldnames, delimiter=',')

                csv_writer.writeheader()
                for t, c, f, s in zip(timeS_x, tempC_y, tempF_y, state_c, strict=False):
                    csv_writer.writerow({
                        'timeS_data': t, 'tempC_data': c,
                        'tempF_data': f, 'state_data': s})
            
            subject = 'Reflow Oven CSV File'
            body = "Here's a copy of your most recent reflow oven data points as a csv\nHave a good day!\n- Yours truly, OvenAI"
            attachments = ['gui/serialdata.csv']
            send_oven_email(subject, body, attachments)
            subject, body, attachments = None, None, None

            messagebox.showinfo('Reflow Oven GUI', f'CSV file sent to {user_email}')
        except Exception as e:
            messagebox.showerror(f'Failed to save CSV: {e}')

# export image popup
def pop_img():
    if user_email == None:
        messagebox.showerror('Reflow Oven GUI', f'Please confirm your email to export IMG')
    else:
        try:
            fig.savefig('reflowOvenPlot.png', dpi=300)            
            
            subject = 'Reflow Oven PNG Image'
            body = "Here's a copy of your most recent reflow oven plot as a png\nHave a good day!\n- Yours truly, OvenAI"
            attachments = ['gui/reflowOvenPlot.png']
            send_oven_email(subject, body, attachments)
            subject, body, attachments = None, None, None

            messagebox.showinfo('Reflow Oven GUI', f'IMG file sent to {user_email}')
        except Exception as e:
            messagebox.showerror(f'Failed to save IMG: {e}')

# EMAIL STUFF
def send_oven_email(subject, body, attachments=None):
    if not user_email:
        print('Email skipped: No recepient address')
        return
    
    msg = EmailMessage()
    msg['Subject'] = subject
    msg['From'] = email_address
    msg['To'] = user_email
    msg.set_content(body)

    if attachments:
        for filepath in attachments:
            with open(filepath, 'rb') as f:
                file_data = f.read()
                if filepath.endswith('.png'):
                    msg.add_attachment(file_data, maintype='image', subtype='png', filename=f.name)
                elif filepath.endswith('.csv'):
                    msg.add_attachment(file_data, maintype='text', subtype='csv', filename=f.name)
                else:
                    messagebox.showerror(f'Could not locate the proper file path: {filepath}')
                    return

    try:      
        with smtplib.SMTP('smtp.gmail.com', 587) as smtp:
            smtp.ehlo()
            smtp.starttls()
            smtp.ehlo()
            smtp.login(email_address, email_password)
            smtp.send_message(msg)
            print(f'Email sent successfully to {user_email}')
    except Exception as e:
        print(f'Failed to send email: {e}')

# MATPLOTLIB FUNCTIONS

# interpolate thermal fill colour
def get_thermal_hex(temp):
    # Maps from 25 - 250 > 0.0 - 1.0
    norm = (temp-25)/(250-25)
    norm = max(0, min(norm, 1.0))

    rgba = thermal_map(norm)
    return mcolors.to_hex(rgba)

# main loop to update graph
def animate(_):
    global timeS_x, tempC_y, tempF_y, state_c
    global poly_verts_C, poly_verts_F, poly_colors
    global poly_C, poly_F
    global timeS_data, tempC_data, tempF_data, state_data
    global last_mode, index

    current_mode = mode_var.get()

    # FSM to check for state transition logic
    # inactive > active
    if last_mode == 0 and current_mode != 0:
        print("Run Started: Resetting Graph Data")
        index = count() 
        timeS_x, tempC_y, tempF_y, state_c = [], [], [], []
        poly_verts_C, poly_verts_F, poly_colors = [], [], []
        lineC.set_data([], [])
        lineF.set_data([], [])
        poly_C.set_verts([])
        poly_F.set_verts([])
    # active > inactive
    elif last_mode != 0 and current_mode == 0:
        print("Run Complete: Finalizing Data...")
        try:
            # send_completion_email()
            pass
        except Exception as e:
            pass
    
    last_mode = current_mode
    
    # skip the graph generation
    if current_mode == 0:
        return lineC, lineF

    #while ser.in_waiting > 0:
    try:
        # recieve and decipher serial data
        #data = ser.readline().decode('utf-8').strip()
        #split_data = data.split(',')
        #timeS_data = 0.5*next(index)
        #tempC_data = float(split_data[0])
        #tempF_data = 1.8*tempC_data+32
        #state_data = str(split_data[1])
        
        # example function generation, to be swapped out for serial input above
        frequency = 0.05 
        amplitude = (250 - 25) / 2
        midpoint = 25 + amplitude
        timeS_data = 0.5*next(index)
        tempC_data = midpoint + amplitude * math.sin(frequency * timeS_data) #float(split_data[0])
        tempF_data = 1.8*tempC_data+32
        state_data = random.choice([m[0] for m in MODES]) #split_data[1]

        # append data to a growing list
        timeS_x.append(timeS_data)
        tempC_y.append(tempC_data)
        tempF_y.append(tempF_data)
        state_c.append(state_data)
        
        # update line to include newest inputs
        lineC.set_data(timeS_x, tempC_y)
        lineF.set_data(timeS_x, tempF_y)

        # more efficient way to fill graph colours
        if len(timeS_x) > 1:
            current_hex = get_thermal_hex(tempC_data)

            x1, x2 = timeS_x[-2], timeS_x[-1]
            y1_C, y2_C = tempC_y[-2], tempC_y[-1]
            y1_F, y2_F = tempF_y[-2], tempF_y[-1]

            # Add slight overlap to eliminate gaps
            overlap = 0.05
            vert_C = [(x1-overlap, 0), (x1-overlap, y1_C), (x2+overlap, y2_C), (x2+overlap, 0)]
            vert_F = [(x1-overlap, 0), (x1-overlap, y1_F), (x2+overlap, y2_F), (x2+overlap, 0)]
            
            poly_verts_C.append(vert_C)
            poly_verts_F.append(vert_F)
            poly_colors.append(current_hex)
            
            poly_C.set_verts(poly_verts_C)
            poly_C.set_facecolors(poly_colors)
            poly_F.set_verts(poly_verts_F)
            poly_F.set_facecolors(poly_colors)

            # as opposed to below
            # axC.fill_between(timeS_x[-2:], tempC_y[-2:], color=current_hex, alpha=1)
            # axF.fill_between(timeS_x[-2:], tempF_y[-2:], color=current_hex, alpha=1)

        # updating legend with max/min/current temperatures
        maxC_t = max(tempC_y)
        minC_t = min(tempC_y)
        axC.legend([f'READING: {tempC_data:.2f}$^o$C\nMAX: {maxC_t:.2f}$^o$C\nMIN: {minC_t:.2f}$^o$C'], loc='upper left', handlelength=0, handletextpad=0)
        maxF_t = max(tempF_y)
        minF_t = min(tempF_y)
        axF.legend([f'READING: {tempF_data:.2f}$^o$F\nMAX: {maxF_t:.2f}$^o$F\nMIN: {minF_t:.2f}$^o$F'], loc='upper left', handlelength=0, handletextpad=0)
        
        # adjust scale of the graph
        axC.relim()
        axC.autoscale_view()
        axF.relim()
        axF.autoscale_view()

    # any corrupted data prints to terminal
    except Exception as e:
        print(f'Error: {e}')

    return lineC, lineF

# MATPLOTLIB GRAPH R01-C0

# graph theme settings
plt.xkcd()
plt.rcParams['font.family'] = 'xkcd script'

# used to progress the index every cycle (# of samples)
index = count()
# just initializing the fsm
last_mode = 0

# create 2 graphs in 1 figure
fig, (axC, axF) = plt.subplots(2, 1)
plt.subplots_adjust(hspace=0.25)

# line settings
lineC, = axC.plot(timeS_x, tempC_y, color="#000000", linestyle='solid', label='Celsius', lw=3)
lineF, = axF.plot(timeS_x, tempF_y, color='#000000', linestyle='solid', label='Fahrenheit', lw=3)

# create graph axes and grids
axC.set_title('Live Temperature Monitor')
axC.set_ylabel('Celsius')
axF.set_ylabel('Fahrenheit')
axF.set_xlabel('Time (s)')
axC.grid(True)
axF.grid(True)

# used for more efficient graph colour fill
poly_C = PolyCollection([], facecolors=[], edgecolors=poly_colors, antialiased=False)
poly_F = PolyCollection([], facecolors=[], edgecolors=poly_colors, antialiased=False)
axC.add_collection(poly_C)
axF.add_collection(poly_F)

# used to place matplotlib graph into tkinter as a widget
graph = FigureCanvasTkAgg(fig, master=graph_frame)
graph.get_tk_widget().grid(row=0, column=0, sticky='nsew')

# calling the main animation loop to update the graph
ani = FuncAnimation(plt.gcf(), animate, interval=500, blit=False, cache_frame_data=False)

# DISPLAY RADIOBUTTON MODES R0-C1

mode_var = IntVar()
mode_var.set(1)

# create disabled radiobuttons
for i, (mode_text, mode_value) in enumerate(MODES):
    mode_rb = Radiobutton(status_frame, variable=mode_var, text=mode_text, value=mode_value, state='disabled')
    mode_rb.grid(row=i, column=0, sticky='w')

# EXPORT CSV AND IMG R2-C0

# export as csv/image buttons
csv_button = Button(exports_frame, text='Export CSV', command=pop_csv, borderwidth=5, relief='raised')
csv_button.grid(row=0, column=0, sticky='nsew', padx=5, pady=5)
img_button = Button(exports_frame, text='Export IMG', command=pop_img, borderwidth=5, relief='raised')
img_button.grid(row=1, column=0, sticky='nsew', padx=5, pady=5)

# DROPDOWN PORTS/DATA R2-C0

ports_var = StringVar()
ports_var.set(PORTS[0])
data_var = StringVar()
data_var.set(DATA[0])
data_var.trace_add('write', validate_mode_change) # watching for mode change

# create dropdown options
ports_dd = OptionMenu(serial_frame, ports_var, *PORTS)
ports_dd.grid(row=0, column=0, sticky='nsew', padx=5, pady=5)
ports_dd.config(borderwidth=5, relief='raised')
data_dd = OptionMenu(serial_frame, data_var, *DATA)
data_dd.config(borderwidth=5, relief='raised')
data_dd.grid(row=1, column=0, sticky='nsew', padx=5, pady=5)

# EMAIL TEXTBOX R2-C0

user_email = None
# python app login to gmail
email_address = 'ovenai.elec291@gmail.com'
email_password = 'pdimngkiuixytrfy'
subject, body, attachments = None, None, None

# create textbox for email
email_tb = Entry(email_frame, border=5)
email_tb.grid(row=0, column=0, sticky='ew')
email_tb.insert(0, '...enter email...')
email_tb.bind('<Return>', save_email)

# OVENAI R1-C1

last_input = None
ai_output = None

# create chat history widget
chat_history = Text(ovenai_frame, wrap=WORD, state='disabled', borderwidth=5, relief='sunken')
chat_history.grid(row=0, column=0, columnspan=2, sticky='nsew', padx=5, pady=5)

# user input textbox left
user_input_label = Label(input_frame, text='User Prompt:', anchor='w')
user_input_label.grid(row=0, column=0, sticky='w', padx=5)
input_tb = Entry(input_frame, border=5)
input_tb.grid(row=1, column=0, sticky='ew', padx=5)
input_tb.insert(0, '...enter prompt...')
input_tb.bind('<Return>', lambda e: get_last_input())

# AI output right
ai_output_label = Label(input_frame, text='Oven AI Response:', anchor='w')
ai_output_label.grid(row=0, column=1, sticky='w', padx=5)
ai_current_output = Entry(input_frame, border=5, state='readonly')
ai_current_output.grid(row=1, column=1, sticky='ew', padx=5)

# TERMINAL R2-C2

# create text widget for terminal
terminal_output = Text(terminal_frame, wrap=WORD, state='disabled', borderwidth=5, relief='sunken', bg='black', fg='lime')
terminal_output.grid(row=0, column=0, sticky='nsew', padx=5, pady=5)

# terminal prints now get redirected to our class
sys.stdout = TextRedirector(terminal_output)
sys.stderr = TextRedirector(terminal_output)

# test print block
print("Oven Controller OS v1.0.4")
print("--------------------------")
print("Status: Initializing UI...")
print("Praying: For Many Bonus Marks...")
print("Believing: Our TA Is A Very Beautiful/Handsome Woman/Man...")
print(f"Screen Resolution: {screen_width}x{screen_height}")
print("Terminal Redirect: SUCCESS")

# PROGRAM LOOP AND TERMINATION

# clears all background processes to prevent memory leaks
def on_closing(event=None):
    ani.event_source.stop()
    root.quit()
    root.destroy()
    sys.exit()

# methods to call the on_closing function
root.protocol('WM_DELETE_WINDOW', on_closing)
root.bind('<Escape>', on_closing)

# loop to constantly monitor GUI
root.mainloop()