#git repo at https://github.com/dgrechka/Rfc

#' RFc: R client for FetchClimate service
#'
#' Extracts raw, averaged environmental data (such as air temperature, precipitation rate, wind speed,
#' etc.) published at the FetchClimate Web service (<http://fetchclimate.org/>) for the specified geo-locations and time bounds from
#' different data sets.
#' 
#' @section Time series fetching functions:
#' fcTimeSeriesYearly, fcTimeSeriesDaily, fcTimeSeriesHourly
#'
#' @section Gridded data fetching functions:
#' fcGrid
#' 
#' @section Listing available data functions:
#' fcDataSets fcVariables
#'
#' @docType package
#' @name RFc
#' 
NULL


#' Availabe data
#' 
#' The default instance of FetchClimate at <http://fetchclimate2.cloudapp.net/> provides the following data
#' 
#' \strong{Environmental variables:}\cr
#' "abshum" : Absolute air humidity (g/m^3)\cr
#' "airt" : Air temperature near surface (Degrees C)\cr
#' "airt_land": Air temperature near surface. Land only areas (Degrees C)\cr
#' "airt_ocean" : Air temperature near surface. Ocean only areas (Degrees C)\cr
#' "depth_ocean" : Depth below sea level. Ocean only areas (meters)\cr
#' "dtr" : Diurnal air temperature rate (Degrees C)\cr
#' "elev" : Elevation above sea level (meters)\cr
#' "elev_land" : Elevation above sea level. Land only a areas (meters)\cr
#' "frs" : Frost days frequency (days/month)\cr
#' "pet": Potential evapotranspiration (mm/month)\cr
#' "prate" : Precipitation rate ()\cr
#' "relhum" : Relative humidity (percentage)\cr
#' "relhum_land" : Relative humidity. Land only area (percentage)\cr
#' "soilmoist" : Soil moisture (mm/m)\cr
#' "sunp" : Sunshine fraction (Percent of maximum possible sunshine)\cr
#' "wet" : Wet days frequency (days/month)\cr
#' "windspeed" : Wind speed at 10m (m/s)\cr
#' "wvp" : Water vapour pressure (hPa)\cr
#' "wvsp" : Water vapour saturation pressure (hPa)\cr
#' 
#' \strong{DataSets [supported variables]:}\cr
#' "CESM1-BGC airt" [airt]\cr
#' "CESM1-BGC prate" [prate]\cr
#' "CpcSoilMoisture" [soilmoist]\cr
#' "CRU CL 2.0" [airt, airt_land, dtr, frs, prate, relhum, relhum_land, sunp, wet, windspeed]\cr
#' "ETOPO1" [elev]\cr
#' "FC1 Variables" [airt_land, airt_ocean, depth_ocean, relhum_land]\cr
#' "GTOPO30" [elev, elev_land]\cr
#' "Malmstrom PET" [pet]\cr
#' "NCEP/NCAR Reanalysis 1 (Gauss T62)" [prate]\cr
#' "NCEP/NCAR Reanalysis 1 (regular grid)" [airt]\cr
#' "WagnerWVSP" [abshum, wvp, wvsp]\cr
#' "WorldClim 1.4" [airt, airt_land, prate]\cr
#' 
#' Note that availavle variables as well as datasets are subject to change in time
#' The list above describes the most recent configuration
#' However specifing timestamp parameter other than "Now" may lead to different set of available data
#' Verify the actual list using `fcVariables()` and `fcDataSets()` functions
#' 
#' @name Availabe data

NULL

#' Release notes
#' 
#' \strong{release 0.1-2}\cr
#' Support for obtaining available datasets and varaibles with\cr
#'      fcDataSets()\cr
#'      fcVaraibles()\cr
#'      \cr
#' \strong{release 0.1-1}\cr
#' Support for fetching simple time series and grids
#' 
#' @name Release notes

require(jsonlite)
require(sp)
require(httr)


internal_fc.formRequestBody <- function(envVar,
                                        lat,lon,
                                        years,
                                        days,
                                        hours,
                                        spatialRegionType,dataSets,timestampStr,
                                        verbose) {
        ## JSON request object. 
        ## The text may be downloaded from http://fetchclimate2.cloudapp.net/form
        
        timeRegion <- list(
                Years=years,
                Days=days,
                Hours=hours,
                IsIntervalsGridYears=unbox(T),
                IsIntervalsGridDays=unbox(T),
                IsIntervalsGridHours=unbox(T)
        )
        
        if(length(lat) == 1)
        {
                lat <- lat
                lon <- lon
        }
        
        domain <- list(
                Lats=lat,
                Lats2=unbox(NA),
                Lons=lon,
                Lons2=unbox(NA),
                TimeRegion=timeRegion,
                Mask=unbox(NA),
                SpatialRegionType=unbox(spatialRegionType)
        )    
        
        if(length(dataSets)==1) {
                if(dataSets=="ANY") {
                        dataSets <- unbox("");# any availalbe
                }
                else {
                        dataSets <- dataSets
                }
        }
        
        
        timestamp<-c()
        if(timestampStr=="NOW") {
                timestamp <- 253404979199999; #max value
        }
        else
        {#"/Date(1317303882420+0500)\/" format
                timestampObj <- as.POSIXct(timestampStr, tz = "UTC", origin="1970-01-01")
                timestamp<-paste("/Date(",as.numeric(timestampObj,digits=20),"000+0000)/",sep='');
        }
        
        
        request <- list(
                EnvironmentVariableName=unbox(envVar),
                ParticularDataSources=dataSets, 
                Domain=domain,
                ReproducibilityTimestamp=unbox(timestamp)
        )
        j <- toJSON(request,digits=20, pretty=TRUE)
        if(verbose) {
                print("request JSON:");
                print(j)        
        }
        
        return(j)
}

internal_fc.getConfiguration<-function(url,timestempStr) {  
        query <- list()
        if(timestempStr=="NOW") {
                # query list remains empty
        }
        else {    
                timestamp <- as.POSIXct(timestempStr, tz = "UTC", origin="1970-01-01")
                query <- list(timestamp=format(timestamp,"%Y-%m-%dT%H:%MZ"))    
        }  
        reply <- GET(url,
                     path="/api/configuration",
                     query=query,
                     accept("text/plain"),
                     content_type("application/json"))
        result <- content(reply)
        return(result)
}

internal_fc.getProvID <- function(configuration,dataSourceName) {
        for(i in 1:length(configuration$DataSources)) {
                if(configuration$DataSources[[i]]$Name==dataSourceName){
                        return(configuration$DataSources[[i]]$ID);
                }    
        }
}

internal_fc.nullToNA <- function(x) {
        x[sapply(x, is.null)] <- NA
        return(x)
}

internal_fc.replaceProvIDwithNames <- function(values,configuration) {
        replaced <- as.numeric(values);
        for(i in 1:length(configuration$DataSources)) {
                current <- configuration$DataSources[[i]]    
                replaced[as.logical(values==current$ID)]<-current$Name
        }
        return(factor(replaced))
}

internal_fc.reformGridResponse <- function(resultList,lats,lons,explicitProvenance=NULL) {#must be private. accepts the decoded JSON recieved from FC result proxy. converts it into matrix
        lonN <- length(lons)
        latN <- length(lats)  
        stratched_lats <- c()
        stratched_lons <- c()
        stratched_values <- c()
        stratched_sd <- c()
        stratched_provenance<-c()    
        
        for(i in 1:lonN) {
                stratched_lons <- c(stratched_lons,rep(lons[i],times=latN))
                stratched_lats <- c(stratched_lats,lats)
                stratched_values <- c(stratched_values,internal_fc.nullToNA(resultList$values[[i]])) #null is MV. replacew with NA
                stratched_sd <- c(stratched_sd,internal_fc.nullToNA(resultList$sd[[i]])) #null is MV. replacew with NA
                if(is.null(explicitProvenance)) {
                        stratched_provenance <- c(stratched_provenance,internal_fc.nullToNA(resultList$provenance[[i]])) #null is MV. replacew with NA
                }
        }
        if(!is.null(explicitProvenance)) {
                stratched_provenance <- rep(explicitProvenance,times=lonN*latN)
        }
        resultdf <- data.frame(lon=stratched_lons,lat=stratched_lats,
                               values=unlist(stratched_values),
                               sd=unlist(stratched_sd),
                               provenance=unlist(stratched_provenance))
        coordinates(resultdf) <- c("lon","lat") #promote to SpatialPointsDataFrame
        proj4string(resultdf) <- CRS("+proj=longlat") #unprojected data
        gridded(resultdf) <- TRUE # promote to SpatialPixelsDataFrame
        
        #resultdf <- as(resultdf, "SpatialGridDataFrame") # promote to SpatialGridDataFrame. creates the full grid
        return(resultdf)
}

internal_fc.reformPointsTimeseries <- function(resultList,explicitProvenance) { #must be private. accepts the decoded JSON recieved from FC result proxy. converts it into matrix        
        N <- length(resultList$values) #locations count
        M <- length(resultList$values[[1]]) # timeseries length
        resV <- matrix(ncol=M,nrow=N)
        resU <- matrix(ncol=M,nrow=N)
        resP <- matrix(ncol=M,nrow=N)
        if(!is.null(explicitProvenance)) {
                resP <- matrix(rep(explicitProvenance,N*M),ncol=M,nrow=N)  
        }  
        
        for(i in 1:N) {
                resV[i,] = unlist(internal_fc.nullToNA(resultList$values[[i]]))
                resU[i,] = unlist(internal_fc.nullToNA(resultList$sd[[i]]))
                if(is.null(explicitProvenance))
                        resP[i,] = unlist(resultList$provenance[[i]])
        }
        resV <- matrix(resV,ncol=M,nrow=N)
        resU <- matrix(resU,ncol=M,nrow=N)
        resP <- matrix(resP,ncol=M,nrow=N)
        return(list(values=resV,sd=resU,provenance=resP))
}

internal_fc.TimeSeries <-function(envVar, #must be private
                                  lat,lon,
                                  years,
                                  days,
                                  hours,
                                  url,dataSets,timestampStr,verbose) {
        N <- length(lat)
        if(length(lon) != N) {
                stop("lon and lat must be the same length");
        }  
        json <- internal_fc.formRequestBody(envVar,
                                            lat,lon,
                                            years,
                                            days,
                                            hours,
                                            spatialRegionType="Points",
                                            dataSets=dataSets,
                                            timestampStr=timestampStr,
                                            verbose=verbose);
        requestProvenance <- length(dataSets)>1 || dataSets=="ANY"  
        
        result <- internal_fc.fetchCore(json,url,requestProvenance,verbose)    
        conf <- internal_fc.getConfiguration(url,timestampStr)
        explicitDs <- c()
        if(requestProvenance){
                explicitDs <- NULL
        }
        else {
                explicitDs<-internal_fc.getProvID(conf,dataSets)
        }
        resultMatrix <- internal_fc.reformPointsTimeseries(result,explicitDs)
        resultMatrix$provenance <- internal_fc.replaceProvIDwithNames(resultMatrix$provenance,conf)
        
        return(resultMatrix)
}

internal_fc.fetchCore <- function(jsonRequest,url,requestProvenance,verbose) {
        #print("requesting JSON")
        #print(jsonRequest)
        replyRaw <- POST(url,path="/api/compute",accept("text/plain"),content_type("application/json"),body=jsonRequest)
        reply<-content(replyRaw)
        if(verbose) {
                print(reply)
        }        
        
        ## wait while processing in progress
        while (substr(reply,1,7)=='pending' || substr(reply,1,8)=='progress') {
                Sys.sleep(5)
                hash=strsplit(reply,"hash=")[[1]][2]    
                replyRaw <- GET(url,
                                path="/api/status",
                                query=list(hash=hash),
                                content_type("application/json"),
                                accept("text/plain")) 
                reply = content(replyRaw)
                if(verbose) {
                        print(reply)
                }
        }
        
        result <- c()
        
        ## get result data
        if(verbose) {
                print("Receiving data...")
        }
        if (substr(reply,1,9)=='completed') {
                msds = substr(reply,11,nchar(reply))    
                vars_to_fetch <- c()
                if(requestProvenance) {
                        vars_to_fetch <- "values,provenance,sd"
                }
                else {
                        vars_to_fetch <- "values,sd"
                }    
                replyRaw <- GET(url,
                                path="/jsproxy/data",
                                query=list(uri=msds,variables=vars_to_fetch),
                                accept("text/plain"),
                                content_type("application/json"),
                                add_headers('Accept-Encoding'= "identity"))    
                #print(replyRaw)
                result=content(replyRaw)
        }
        return(result);
}

#' Fetches information about available datasets
#' @import httr
#' @import jsonlite
#' @import sp
#' @export
#' @param url The URL of the service to get the information about
#' @param timestamp A character scalar. A string containing the time for which the result must correspond. The format is "YYYY-MM-DD". The special value "NOW" fetch the data using the latest FetchClimate configuration available.
#' @return Type: list\cr
#' Contains a descriptions of the datasets available to fetch the data from
#' 
#' @examples
#' #Getting currently available datasets
#' 
#' fcDataSets()
#' 
#' #Getting datasets available on 1 June 2016
#' 
#' fcDataSets(timestamp='2016-06-01')
#' 
#' #Listing varaibles that are avaialable from "CRU CL 2.0" dataset
#' 
#' fcDataSets(timestamp='2016-06-01')$`CRU CL 2.0`$Variables
#' 
fcDataSets <- function(url='http://fetchclimate2.cloudapp.net/',timestamp="NOW") {
        configuration <- internal_fc.getConfiguration(url,timestamp)
        result <- list()
        for(i in 1:length(configuration$DataSources)) {
                currentDs <- configuration$DataSources[[i]]
                dataset <- list(
                        Name=currentDs$Name,
                        Description=currentDs$Description,
                        Copyright=currentDs$Copyright,
                        Variables=as.character(currentDs$ProvidedVariables))
                
                result[[currentDs$Name]] <- dataset
        }
        return(result)
}

#' Fetches information about available variables
#' @import httr
#' @import jsonlite
#' @import sp
#' @inheritParams fcDataSets
#' @export
#' @return Type: list\cr
#' Contains a descriptions of the variables available for fetching
#' 
#' @examples
#' #Getting currently available variables
#' 
#' fcVariables()
#' 
#' #Getting variables available on 1 June 2016
#' 
#' fcVariables(timestamp='2016-06-01')
#' 
#' #Obtaining units of "prate" variable
#' 
#' fcVariables(timestamp='2016-06-01')$`prate`$Units
#' 
fcVariables <- function(url='http://fetchclimate2.cloudapp.net/',timestamp="NOW") {
        configuration <- internal_fc.getConfiguration(url,timestamp)
        result <- list()
        for(i in 1:length(configuration$EnvironmentalVariables)) {
                currentVar <- configuration$EnvironmentalVariables[[i]]
                v <- list(
                        Name=currentVar$Name,
                        Description=currentVar$Description,
                        Units=currentVar$Units)
                
                result[[currentVar$Name]] <- v
        }
        return(result)
}

#' Fetches time series data for a set of locations
#' 
#' For a given set of geo-locations (lat - lon pairs) and given time interval the time series is formed by splitting the time interval either by years or by days or by hours
#' 
#' 
#' @name TimeSeries
#' @param variable An identifier of the variable to fetch. \cr
#' To get the list of available variables use `fcVariables()` function or see "Available data" section of documentaion
#' @param latitude A numeric vector. Latitudes of the point set to fetch values for
#' @param longitude A numeric vector. Longitudes of the point set to fetch values for
#' @param firstYear A numeric scalar. Temporal coverage definition: The lower bound of years over which the averaging is performed
#' @param lastYear A numeric scalar. Temporal coverage definition: The upper bound of years over which the averaging is performed
#' @param firstDay A numeric scalar. Temporal coverage definition: The lower bound of the days interval within each year over which the averaging is performed
#' @param lastDay A numeric scalar. Temporal coverage definition: The upper bound of the days interval within each year over which the averaging is performed
#' @param startHour A numeric scalar. Temporal coverage definition: The lower bound of the hours interval within each day over which the averaging is performed
#' @param stopHour A numeric scalar. Temporal coverage definition: The upper bound of the hours interval within each day over which the averaging is performed
#' @param url The URL of the service to query the data from
#' @param dataSets A character vector. An identifier of the data set to fetch the data from. The special value "ANY" enables data stitching from all available data sets.
#' @param reproduceFor A character scalar. A string containing the time for which the result must correspond. The format is "YYYY-MM-DD". The special value "NOW" fetch the data using the latest FetchClimate configuration available.
#' @param verbose A logical scalar. If set to TRUE the method outputs its actions verbosely
#' @return A list. Contains the following entries: values, sd, provenance.
#' Each of entries have the following dimensions (using values as an example):
#' length(values) = point set count * time series length;
#' nrow(values) = point set count;
#' ncol(values) = time series length;

#' @examples
#' #Fetching a whole year average time series
#' #(varing year one by one starting from 1950 till 2000 inclusevly)
#' #for a single geo point
#' fcTimeSeriesYearly(variable="airt",latitude=75.5, longitude=57.7,firstYear=1950,lastYear=2000)
#'
#' #Fetching diurnal temperature variation (hourly time series) in Moscow for a July 2008
#' fcTimeSeriesHourly(variable="airt",latitude=55.5, longitude=37.3,
#'      firstDay=183,lastDay=213,
#'      firstYear=2008,lastYear=2008,
#'      startHour=0,stopHour=23)
#' 
NULL

#' @describeIn TimeSeries Yearly timeseries fetching
#' @import httr
#' @import jsonlite
#' @import sp
#' @export
fcTimeSeriesYearly<-function(
        variable,
        latitude,longitude,
        firstYear,lastYear,
        firstDay=1,lastDay=365,
        startHour=0,stopHour=23,
        url="http://fetchclimate2.cloudapp.net/",
        dataSets="ANY",
        reproduceFor="NOW",
        verbose=F
) {
        #envVar is string
        #lat,lon are vectors with the same length (can be length of 1).
        #firstYear,lastYear are scalars
        
        #return a list with NxM matrices (values,sd,provenance). N = length(lat), M = timeseries length
        
        years <- seq(from=firstYear,to=lastYear+1,by=1)
        days <- c(firstDay,lastDay+1)
        hours <- c(startHour,stopHour+1)
        
        resultMatrix <-internal_fc.TimeSeries(variable,latitude,longitude,years,days,hours,url,dataSets,reproduceFor,verbose)
        
        resultMatrix$years <- years[1:(length(years)-1)]
        
        return(resultMatrix)
}

#' @describeIn TimeSeries Daily timeseries fetching
#' @import httr
#' @import jsonlite
#' @import sp
#' @export
fcTimeSeriesDaily<-function(
        variable,
        latitude,longitude,
        firstDay=1,lastDay=365,
        firstYear=1961,lastYear=1990,
        startHour=0,stopHour=23,
        url="http://fetchclimate2.cloudapp.net/",
        dataSets="ANY",
        reproduceFor="NOW",
        verbose=F
        ) {
        #envVar is string
        #lat,lon are vectors with the same length (can be length of 1).  
        #firstDay,lastDay are scalars
        
        #return a list with NxM matrices (values,sd,provenance). N = length(lat), M = timeseries length
        
        
        years <- c(firstYear,lastYear+1)
        days <- seq(from=firstDay,to=lastDay+1,by=1)
        hours <- c(startHour,stopHour+1)
        
        resultMatrix <-internal_fc.TimeSeries(variable,latitude,longitude,years,days,hours,url,dataSets,reproduceFor,verbose)
        
        resultMatrix$days <- days[1:(length(days)-1)]
        
        return(resultMatrix)
}

#' @describeIn TimeSeries Hourly timeseries fetching
#' @import httr
#' @import jsonlite
#' @import sp
#' @export
fcTimeSeriesHourly<-function(
        variable,
        latitude,longitude,
        startHour,stopHour,
        firstYear=1961,lastYear=1990,
        firstDay=1,lastDay=365,
        url="http://fetchclimate2.cloudapp.net/",
        dataSets="ANY",
        reproduceFor="NOW",
        verbose=F) {
        #envVar is string
        #lat,lon are vectors with the same length (can be length of 1).
        #startHour,stopHour are scalars
        
        #return a list with NxM matrices (values,sd,provenance). N = length(lat), M = timeseries length
        
        
        years <- c(firstYear,lastYear+1)
        days <- c(firstDay,lastDay+1)
        hours <- seq(from=startHour,to=stopHour+1, by = 1)
        
        resultMatrix <-internal_fc.TimeSeries(variable,latitude,longitude,years,days,hours,url,dataSets,reproduceFor,verbose)
        
        resultMatrix$hours <- hours[1:(length(hours)-1)]
        
        return(resultMatrix)
}

#' Fetches gridded data
#' @import httr
#' @import jsonlite
#' @import sp
#' @export
#' @param latitudeFrom A numeric scalar. The lower latitude bound of the spatial grid
#' @param latitudeTo A numeric scalar. The upper latitude bound of the spatial grid
#' @param latitudeBy A numeric scalar. The step of the grid along latitudes
#' @param longitudeFrom A numeric scalar. The lower longitude bound of the spatial grid
#' @param longitudeTo A numeric scalar. The upper longitude bound of the spatial grid
#' @param longitudeBy A numeric scalar. The step of the grid along longitudes.
#' @param verbose A logical scalar. If set to TRUE the method outputs its actions verbosely
#' @inheritParams TimeSeries
#' @return Type: SpatialPixelsDataFrame (from sp package)
#' Contains a grid definition the following fields: values, sd, provenance
#' 
#' @examples
#' #Fetching average potential evapotransiration for the upper part of Africa continent
#' #for Januries 2000-2010
#' #With 1 degree grid resolution
#' 
#' fcGrid(variable="pet",
#'      latitudeFrom=0, latitudeTo=35,latitudeBy=1,
#'      longitudeFrom= -25, longitudeTo=50, longitudeBy=1,
#'      firstDay=1,lastDay=31,
#'      firstYear=2000,lastYear=2010)

fcGrid <- function(
        variable,
        latitudeFrom,latitudeTo,latitudeBy,
        longitudeFrom,longitudeTo,longitudeBy,  
        firstYear=1961,lastYear=1990,
        firstDay=1,lastDay=365,
        startHour=0,stopHour=24,
        url="http://fetchclimate2.cloudapp.net/",
        dataSets="ANY",
        reproduceFor="NOW",
        verbose=F) {
        
        lats <- seq(from=latitudeFrom,to=latitudeTo,by=latitudeBy)
        lons <- seq(from=longitudeFrom,to=longitudeTo,by=longitudeBy)
        
        years <- c(firstYear,lastYear+1)
        days <- c(firstDay,lastDay+1)
        hours <- c(startHour,stopHour)
        
        requestBody <- internal_fc.formRequestBody(variable,
                                                   lats,lons,
                                                   years,days,hours,
                                                   "PointGrid",dataSets,reproduceFor,verbose)
        requestProvenance <- length(dataSets)>1 || dataSets=="ANY"  
        response <- internal_fc.fetchCore(requestBody,url,requestProvenance,verbose)
        conf <- internal_fc.getConfiguration(url,reproduceFor)
        explicitDs <- c()
        if(requestProvenance){
                explicitDs <- NULL
        }
        else {
                explicitDs<-internal_fc.getProvID(conf,dataSets)
        }
        spObj <- internal_fc.reformGridResponse(response,lats,lons,explicitDs)  
        
        
        spObj$provenance <- internal_fc.replaceProvIDwithNames(spObj$provenance,conf)
        
        return(spObj);
}