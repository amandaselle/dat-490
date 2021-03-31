##retrieves historical data for ticker symbols not found using the Alpha Vantage API with a webscraper

####### NOTICE ###############
# -- directories for testing are for testing only. Will need to be changed depending on the machine this script is being run on -- #
# -- update:  -- #



#import dependencies
import pyodbc
import pandas as pd
from fredapi import Fred
import pandas_datareader
from pandas_datareader import data
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.common.exceptions import ElementClickInterceptedException
from selenium.webdriver.chrome.options import Options
from urllib.request import Request, urlopen
import re
from html_table_extractor.extractor import Extractor as ext
import requests
from six.moves import urllib
from bs4 import BeautifulSoup
import datetime
from dateutil.relativedelta import relativedelta
import os
import sys
from selenium.webdriver.common.desired_capabilities import DesiredCapabilities
from selenium.webdriver.firefox.options import Options

#Create script as function to pass arguments from ssis package
def IndexWebScraper(server,database,csvPath):

    #Define variables
    startDate = datetime.datetime.today()-relativedelta(years=5)
    SstartDate = str(startDate)
    endDate = datetime.datetime.today()
    SendDate = str(endDate)
    fstartDate = startDate.strftime("%m/%d/%Y")
    fendDate = endDate.strftime("%m/%d/%Y")
    print("Connecting to database")
    conn = pyodbc.connect('Driver={SQL Server};'
                    'Server='+server+';'   
                    'Database='+database+';'  
                    'UID=<SERVICE ACCOUNT>;'
                    'PWD=<PWD>;'
                    'Trusted_Connection=no;')
    cursor = conn.cursor()

    sql = 'SELECT distinct Symbol,InvestingLink FROM <SYMBOLS TABLE> WHERE InvestingLink is not null'
    scraper = pd.read_sql(sql,conn)
    print("retrieved data from database")
    symbols = scraper["Symbol"]
    syms = []
    for i in symbols:
        syms.append(i)
    links = scraper["InvestingLink"]
    lks = []
    for i in links:
        lks.append(i)
    iterator2 = len(syms)

    #options = webdriver.ChromeOptions()
    #options.add_argument('headless')

    while iterator2 > 0:
        url = lks[iterator2-1]
        print(url)
        print("Launching")
        binary = r'C:\Program Files\Mozilla Firefox\firefox.exe'
        cap = DesiredCapabilities().FIREFOX
        options = Options()
        options.binary = binary
        cap["marionette"] = True
        d = webdriver.Firefox(capabilities=cap, firefox_options=options,executable_path="E:\\geckodriver.exe")

        #)

        d.get(url)
        print("Launched")
        valid = '1234567890.' #valid chars for float
        def sanitize(data):
            x = ''.join(filter(lambda char: char in valid, data))
            return float(x)
        retry = []
        try:
            #d.execute_script("window.scrollTo(0, 300)")
            # Tries to click an element
            #d.find_element_by_id('widgetFieldDateRange').click()
            d.find_element_by_id('widgetField').click()
            sDate  = d.find_element_by_id('startDate') # set start date input element into variable
            sDate.clear() #clear existing entry
            sDate.send_keys(fstartDate) #add custom entry
            eDate = d.find_element_by_id('endDate') #repeat for end date
            eDate.clear()
            eDate.send_keys(fendDate)
            d.find_element_by_id('applyBtn').click()
            currentURL = d.current_url
            req = Request(currentURL,headers={"User-Agent": 'Mozilla/5.0'})
            webpage = urlopen(req).read()
            page_soup = BeautifulSoup(d.page_source, 'html.parser')
            d.close()
            data = page_soup.find('table',class_='genTbl closedTbl historicalTbl')
            extractor = ext(data)
            extractor.parse()
            lst = extractor.return_list()
            df = pd.DataFrame(lst)

            df.to_csv(csvPath+syms[iterator2-1]+'.csv',index=False,header=False)

            df2 = pd.read_csv(csvPath+syms[iterator2-1]+'.csv')
            countRows = df2.shape[0]
            dataSource = []
            contractName = []
            for i in range(0,countRows):
                dataSource.append(syms[iterator2-1])
            df2['DataSource'] = dataSource
            for i in range(0,countRows):
                contractName.append(syms[iterator2-1])
            df2['ContractName'] = contractName
            df3 = df2.replace(to_replace='-',value='')
            df3['Date'] = df3.Date.apply(lambda x: pd.to_datetime(x).strftime('%m/%d/%Y'))

            df3.to_csv(csvPath+syms[iterator2-1]+'.csv',index=False,header=True)
            #reorganize csv contents for ssis package

            dfd = pd.read_csv(csvPath+syms[iterator2-1]+'.csv')
            dfd['Price'] = dfd['Price'].astype(str).str.replace(',','')
            dfd['Open'] = dfd['Open'].astype(str).str.replace(',','')
            dfd['High'] = dfd['High'].astype(str).str.replace(',','')
            dfd['Low'] = dfd['Low'].astype(str).str.replace(',','')
            dfd = dfd.drop(['Change %'],axis=1)
            dfdf = dfd.rename(columns={"Vol.":"Volume","Price":"Close"})
            dfdf['Volume'] = dfdf['Volume'].astype(str).str.replace('M','000000')
            dfdf['Volume'] = dfdf['Volume'].astype(str).str.replace('B','000000000')
            dfdf['Volume'] = dfdf['Volume'].astype(str).str.replace('K','000')
            dfdf['Volume'] = dfdf['Volume'].astype(str).str.replace('.','')
            dfdf2 = dfdf[['Date','Open','Close','High','Low','Volume','DataSource','ContractName']]

            dfdf2.to_csv(csvPath+syms[iterator2-1]+'.csv',index=False)

            #d.close()
            d.quit()

            iterator2-=1
        except ElementClickInterceptedException:
            #intercepted clicks are passed and retried later
            pass




IndexWebScraper(sys.argv[1],sys.argv[2],sys.argv[3])

#print('Database='+sys.argv[2]+';')

# exception handler for error on automation
def show_exception_and_exit(exc_type, exc_value, tb):
    import traceback
    traceback.print_exception(exc_type, exc_value, tb)
    raw_input("Press key to exit.")
    sys.exit(-1)

import sys
sys.excepthook = show_exception_and_exit


fred = Fred(api_key=<API KEY>)

def getData(sym):
    for i in sym:
        data = fred.get_series(i)

        datasource = []
        df = pd.DataFrame(data)
        df.reset_index()
        rows = data.shape[0]
        for x in range(0,rows):
            datasource.append(i)

        df['DataSource'] = datasource
        df.columns=['Value','DataSource']

        

def getDataURN(sym):
    for i in sym:
        data = fred.get_series(i)

        datasource = []
        df = pd.DataFrame(data)
        df.reset_index()
        rows = data.shape[0]
        for x in range(0,rows):
            datasource.append(i)

        df['DataSource'] = datasource
        df.columns=['Value','DataSource']

        

symList = ['COBP1FH','DPRIME','CPIAUCSL','PCE']
#URNList = ['COLAPL7URN','COARCH7URN','LAUCN080670000000006A','LAUCN080070000000006A']
URNList = ['COLAPL7URN','COARCH7URN','COLAPL7LFN','COARCH7LFN']

getData(symList)
getDataURN(URNList)
