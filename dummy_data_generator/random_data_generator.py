import psycopg2
import random
import json

PORT = "8888" # Port number Postgre Server is runnin on
DATABASE = "IoT_DB" # Name of the Database
USER = "michaelstone" # Database user
HOST = "localhost" # DBS host
PASSWORD = "" #optional password if you are using one locally
CONTROLLER_TYPES = ["C02", "ELECTRICITY", "MOTION"] # categories of modules
NUM_OF_BEACONS = 10 # Beacons
NUM_OF_CONTROLLERS = 10 * NUM_OF_BEACONS # microcontrollers with sensors
MAC_ADDRS = set() # a collection of Becaon mac_addrs
CONTROLLER_MACS = set() # collection of controleer mac_addrs

''' Some time definitons to help generate Data'''
DAY_HOURS = 24
NUM_OF_DAYS = 1
NUM_OF_WEEKS = 4
# Currently not in use
# NUM_OF_MONTHS = 0
# DATA_PER_MIN = 1 
'''-------------------------------------------'''

# Database connection
conn = None

'''Helper functions to create tables'''

def create_beacons(cur):
    cur.execute("CREATE TABLE IF NOT EXISTS iot_office.Beacons(Beacon macaddr PRIMARY KEY)")

def create_controllerTypes(cur):
    cur.execute('CREATE TABLE IF NOT EXISTS iot_office.Controller_types(Controller_type varchar(20) PRIMARY KEY)')

def create_controllers(cur):
    cur.execute("CREATE TABLE IF NOT EXISTS iot_office.Controllers(Controller macaddr PRIMARY KEY,Beacon macaddr REFERENCES iot_office.beacons(beacon),Controller_type varchar(20) REFERENCES iot_office.controller_types(controller_type))")

def create_sensor_data(cur):
    cur.execute('CREATE TABLE IF NOT EXISTS iot_office.Sensor_Data(Controller macaddr REFERENCES iot_office.controllers(controller),raw_data JSON,time_recv TIMESTAMP);')    

'''--------------------------------------------------------------'''

'''Create Schema tables'''
def create_tables(cur):
    create_beacons(cur)
    create_controllerTypes(cur)
    create_controllers(cur)
    create_sensor_data(cur)

'''Creates CAST from varchar to maccaddr'''

def varchar_to_macaddr(cur):
    cur.execute("CREATE OR REPLACE FUNCTION varchar_to_macaddr(varchar)" + 
                "RETURNS macaddr LANGUAGE SQL AS $$" +
                    "SELECT macaddr_in($1::cstring);"
                "$$ IMMUTABLE;")

    # comment this line out after use since you can recreate CAST
    cur.execute("CREATE CAST (varchar AS macaddr) WITH FUNCTION varchar_to_macaddr(varchar) AS IMPLICIT IF NOT EXISTS;")

'''Remove all tables'''
def delete_all_beacons(cur):
    cur.execute("DELETE FROM iot_office.beacons")

def delete_all_controller_types(cur):
    cur.execute("DELETE FROM iot_office.controller_types")

def delete_all_controllers(cur):
    cur.execute("DELETE FROM iot_office.controllers")

def delete_all_data(cur):
    cur.execute("DELETE FROM iot_office.sensor_data")

'''---------------------------------------------------'''

'''Generate random mac_addrs for beacons and controllers'''
def generate_macaddr(cur):
    varchar_to_macaddr(cur)
    
    while len(MAC_ADDRS) != 10:
        random_mac = "02:00:00:%02x:%02x:%02x" % (random.randint(0, 255),
                             random.randint(0, 255),
                             random.randint(0, 255))
        #print(random_mac)
        if random_mac not in MAC_ADDRS:
            MAC_ADDRS.add(random_mac)
            cur.execute("INSERT INTO iot_office.beacons VALUES (\'" +random_mac + "\'::varchar)")

def generate_controllers(cur):

    while len(CONTROLLER_MACS) != 100:
        random_mac = "01:00:00:%02x:%02x:%02x" % (random.randint(0, 255),
                             random.randint(0, 255),
                             random.randint(0, 255))
        if random_mac not in CONTROLLER_MACS:
            CONTROLLER_MACS.add(random_mac)
        
    controllers = list(CONTROLLER_MACS)
    print(controllers)
    for beacon_addr in MAC_ADDRS:
        for i in range(0, int(NUM_OF_CONTROLLERS/NUM_OF_BEACONS)):
            family = CONTROLLER_TYPES[random.randint(0,2)]
            cur.execute("INSERT INTO iot_office.controllers VALUES(\'" + controllers.pop() + "\', \'" + beacon_addr + "\', \'" + family + '\')')

'''---------------------------------------------------------------------'''

'''Generate Controller Types'''
def generate_controller_types(cur, family=CONTROLLER_TYPES):
    if family is not None:
        for name in family:
            cur.execute("INSERT INTO iot_office.controller_types VALUES (\'" + name+ "\')")

'''Generate random Data for C02, power, and density'''
def generate_co2():
    c02_reading = random.randint(400,10000)
    temprature = random.randint(0,100)
    humidity =  random.randint(0,100)
    data = {
        "C02": c02_reading,
        "Temp": temprature,
        "Humidity": humidity
    }

    return json.dumps(data)

def generate_power():
    power = random.randint(0,100)
    khw = random.randint(0,20)
    current = random.randint(0, 3)
    data = {
        "Power": power,
        "KwH": khw,
        "Current": current
    }

    return json.dumps(data)
    
def generate_density():
    num_people = random.randint(0,50)
    data = {
        "Density": num_people
    }

    return json.dumps(data)

'''------------------------------------'''

'''Generate timestamps by the min for NUM_OF_WEEKS for a given microcontroller of a type
   NUM_OF_WEEKS should not exceed 4. Not month incrementing implemented
'''
def generate_weekly_data(mac_addr,type, cur):
    days = NUM_OF_WEEKS * 7
    mins = 0
    hours = 0
    day = 1
    data = ""
    for i in range(1,days+1):
        for i in range(DAY_HOURS * 60):
            if type == "C02":
                data = generate_co2()
            if type == "ELECTRICITY":
                data = generate_power()
            if type == "MOTION":
                data = generate_density()

            date = "2021-03-{day} {hours}:{mins}:00".format(day = day, hours = hours, mins = mins)
            cur.execute("INSERT INTO iot_office.sensor_data VALUES(\'{mac_addr}\', \'{data}\', \'{date}\')".format(mac_addr = mac_addr, data = data, date = date))
            mins += 1
            if mins == 60:
                mins = 0
                hours += 1
            if hours == 24:
                day += 1
                hours = 0
            
'''Adds random Data and timestamp to table'''
def generate_sensor_data(cur):
    cur.execute("SELECT controller, controller_type FROM iot_office.controllers")
    rows = cur.fetchall()
    for row in rows:
        generate_weekly_data(row[0], row[1], cur)

'''Remove all old tavles and generate new ones'''
def generate_random_data():
    try:
        cur = conn.cursor()
        delete_all_data(cur)
        delete_all_controllers(cur)
        delete_all_controller_types(cur)
        delete_all_beacons(cur)
        delete_all_data(cur)
        generate_macaddr(cur)
        generate_controller_types(cur)
        generate_controllers(cur)
        generate_sensor_data(cur)
        conn.commit()
        cur.close()
        
    except(Exception, psycopg2.DatabaseError) as error:
        print(error)

'''Connect to DB and generate SCHEMA if not already exists'''
def connect():
    try:
        global conn
        print("Connecting to DBS")
        conn = psycopg2.connect(host=HOST, port=PORT, database=DATABASE, user=USER)
        cur = conn.cursor()
        cur.execute("CREATE SCHEMA IF NOT EXISTS iot_office")
        create_tables(cur)
        conn.commit()
        cur.close()

    except(Exception, psycopg2.DatabaseError) as error:
        print(error)
        

if __name__ == '__main__':
    connect()
    generate_random_data()
    