import requests, json
import numpy as np
import matplotlib.pyplot as plt
from tkinter import *
from tkinter import messagebox
from PIL import ImageTk, Image

root = Tk()
root.title('Reflow Oven GUI')
root.geometry('1920x1080')
root.iconbitmap('litovenicon.ico')

image = Image.open('crumpledpaper_bg.jpg')
image = image.resize((1920, 1080), Image.Resampling.LANCZOS)
bg_img = ImageTk.PhotoImage(image)
bg_label = Label(root, image=bg_img)
bg_label.place(x=0, y=0, relwidth=1, relheight=1)

# INPUT FUNCTIONS

def email_click():
    global user_email
    user_email = email_tb.get()
    myLabel = Label(email_frame, text=f'Email Saved: {user_email}')
    myLabel.grid(row=1, column=0, sticky=W)

def update_mode(new_value):
    mode_var.set(new_value)

def pop_csv():
    if user_email == None:
        messagebox.showerror('CSV Confirmation', f'Please confirm your email to export CSV')
    else:
        messagebox.showinfo('CSV Confirmation', f'CSV file sent to {user_email}')
    
def pop_img():
    if user_email == None:
        messagebox.showerror('IMG Confirmation', f'Please confirm your email to export IMG')
    else:
        messagebox.showinfo('IMG Confirmation', f'IMG file sent to {user_email}')

#def graph():
    #matplotlibcode

# MATPLOTLIB GRAPH C0R0



# EXPORT CSV AND IMG C0R1

export_frame = LabelFrame(root, text='Forward CSV or IMG files to Email', padx=5, pady=5)
export_frame.grid(row=1, column=0, padx=5, pady=5, columnspan=1)

csv_button = Button(export_frame, text='Export CSV', command=pop_csv, padx=10, pady=10)
csv_button.grid(row=0, column=0)

img_button = Button(export_frame, text='Export IMG', command=pop_img, padx=10, pady=10)
img_button.grid(row=0, column=1)

# DISPLAY RADIOBUTTON MODES C1R0

mode_frame = LabelFrame(root, text='System Status', padx=5, pady=5)
mode_frame.grid(row=0, column=1, padx=5, pady=5)

MODES = [
    ('Inactive', 0),
    ('Ramp to Soak', 1),
    ('Preheat/Soak', 2),
    ('Ramp to Peak', 3),
    ('Reflow', 4),
    ('Cooling', 5)
]

mode_var = IntVar()
mode_var.set(0)

for mode_text, mode_value in MODES:
    mode_rb = Radiobutton(mode_frame, variable=mode_var, text=mode_text, value=mode_value, state='disabled')
    mode_rb.pack(anchor=W)

# DROPDOWN COM PORTS C1R1

comports_frame = LabelFrame(root, text='Select Serial COM Port', padx=5, pady=5)
comports_frame.grid(row=1, column=1, padx=5, pady=5, columnspan=1)

COMPORTS = ['COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6']

comports_var = StringVar()
comports_var.set(COMPORTS[0])

comports_dd = OptionMenu(comports_frame, comports_var, *COMPORTS)
comports_dd.pack()

# EMAIL TEXTBOX C1R2

user_email = None

email_frame = LabelFrame(root, text='Enter Email for Notifications and Exports', padx=5, pady=5)
email_frame.grid(row=2, column=1, padx=5, pady=5, columnspan=1)

email_tb = Entry(email_frame, width=50, border=5)
email_tb.grid(row=0, column=1)
email_tb.insert(0, '...')

email_button = Button(email_frame, command=email_click, text='Confirm', fg="#000000", padx=10, pady=10)
email_button.grid(row=0, column=0)

# OVENAI API C1R3

try:
    api_request = requests.get('openaikeyhere')
    api = json.loads(api_request.content)
except Exception as e:
    api = e

root.mainloop()