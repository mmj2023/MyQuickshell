pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import "../Common/suncalc.js" as SunCalc

// Standalone weather service for MyQuickshell.
// Uses open-meteo API + curl. No DMS dependencies.
Singleton {
  id: root

  property var weather: ({
    "available": false, "loading": false,
    "temp": 0, "tempF": 0, "feelsLike": 0, "feelsLikeF": 0,
    "city": "", "country": "", "wCode": 0,
    "humidity": 0, "wind": 0, "sunrise": "06:00", "sunset": "18:00",
    "pressure": 0, "precipitationProbability": 0, "isDay": true,
    "rawSunrise": "", "rawSunset": "", "forecast": [], "hourlyForecast": []
  })
  property var location: null
  property string lastFetchError: ""
  property int refCount: 0
  property int lastFetchTime: 0
  property int retryAttempts: 0
  readonly property int _minFetchInterval: 30000

  readonly property var _dayIcons: ({
    "0":"sunny","1":"partly_cloudy_day","2":"partly_cloudy_day","3":"cloud",
    "45":"foggy","48":"foggy",
    "51":"rainy","53":"rainy","55":"rainy","56":"rainy","57":"rainy",
    "61":"rainy","63":"rainy","65":"rainy","66":"rainy","67":"rainy",
    "71":"cloudy_snowing","73":"cloudy_snowing","75":"snowing_heavy","77":"cloudy_snowing",
    "80":"rainy","81":"rainy","82":"rainy","85":"cloudy_snowing","86":"snowing_heavy",
    "95":"thunderstorm","96":"thunderstorm","99":"thunderstorm"
  })
  readonly property var _nightIcons: ({
    "0":"clear_night","1":"clear_night","2":"partly_cloudy_night","3":"cloud",
    "45":"foggy","48":"foggy",
    "51":"rainy","53":"rainy","55":"rainy","56":"rainy","57":"rainy",
    "61":"rainy","63":"rainy","65":"rainy","66":"rainy","67":"rainy",
    "71":"cloudy_snowing","73":"cloudy_snowing","75":"snowing_heavy","77":"cloudy_snowing",
    "80":"rainy","81":"rainy","82":"rainy","85":"cloudy_snowing","86":"snowing_heavy",
    "95":"thunderstorm","96":"thunderstorm","99":"thunderstorm"
  })
  readonly property var _conditions: ({
    "0":"Clear Sky","1":"Clear Sky","2":"Partly Cloudy","3":"Overcast",
    "45":"Fog","48":"Fog","51":"Drizzle","53":"Drizzle","55":"Heavy Drizzle",
    "56":"Freezing Drizzle","57":"Freezing Drizzle",
    "61":"Light Rain","63":"Rain","65":"Heavy Rain",
    "66":"Light Freezing Rain","67":"Heavy Freezing Rain",
    "71":"Light Snow","73":"Snow","75":"Heavy Snow","77":"Snow Grains",
    "80":"Light Showers","81":"Showers","82":"Heavy Showers",
    "85":"Light Snow Showers","86":"Heavy Snow Showers",
    "95":"Thunderstorm","96":"Thunderstorm w/ Hail","99":"Thunderstorm w/ Hail"
  })


  property var moonPhaseNames: ["moon_new", "moon_waxing_crescent", "moon_first_quarter", "moon_waxing_gibbous", "moon_full", "moon_waning_gibbous", "moon_last_quarter", "moon_waning_crescent"]

  function getMoonPhase(date) {
    const phases = moonPhaseNames
    const iconCount = phases.length
    const moon = SunCalc.getMoonIllumination(date)
    const index = ((Math.floor(moon.phase * iconCount + 0.5) % iconCount) + iconCount) % iconCount
    return phases[index]
  }

  function getMoonAngle(date) {
    if (!location) return 0
    const pos = SunCalc.getMoonPosition(date, location.latitude, location.longitude)
    return pos.parralacticAngle
  }

  function getLocation() {
    return location
  }

  function getSunDeclination(date) {
    return SunCalc.sunCoords(SunCalc.toDays(date)).dec * 180 / Math.PI
  }

  function getSunTimes(date) {
    if (!location) return null
    return SunCalc.getTimes(date, location.latitude, location.longitude, 0)
  }

  function getEcliptic(date, points = 60) {
    if (!location) return null
    const lat = location.latitude
    const lon = location.longitude
    const times = SunCalc.getTimes(date, lat, lon)
    const solarNoon = times.solarNoon
    const eclipticPoints = []
    const sunIsNorth = getSunDeclination(date) > lat
    const transitAzimuth = sunIsNorth ? 0 : Math.PI

    for (let i = 0; i <= points; i++) {
      const t = new Date(solarNoon.getTime() + (i / points) * 24 * 60 * 60 * 1000)
      const pos = SunCalc.getPosition(t, lat, lon)
      let h = (((pos.azimuth - transitAzimuth) / (2 * Math.PI)) + 1) % 1
      h = Math.max(0, Math.min(1, h))
      let v = Math.sin(pos.altitude)
      v = Math.max(-1, Math.min(1, v))
      eclipticPoints.push({ h, v })
    }
    return eclipticPoints.sort((a, b) => a.h - b.h)
  }

  function getCurrentSunTime(date) {
    const times = getSunTimes(date)
    if (!times) return null
    const dateObj = new Date(date)

    const periods = [
      { name: "Dawn", start: new Date(times.nightEnd), end: new Date(times.nauticalDawn) },
      { name: "Dawn", start: new Date(times.nauticalDawn), end: new Date(times.dawn) },
      { name: "Dawn", start: new Date(times.dawn), end: new Date(times.sunrise) },
      { name: "Sunrise", start: new Date(times.sunrise), end: new Date(times.sunriseEnd) },
      { name: "Golden Hour", start: new Date(times.sunriseEnd), end: new Date(times.goldenHourEnd) },
      { name: "Morning", start: new Date(times.goldenHourEnd), end: new Date(times.solarNoon) },
      { name: "Afternoon", start: new Date(times.solarNoon), end: new Date(times.goldenHour) },
      { name: "Golden Hour", start: new Date(times.goldenHour), end: new Date(times.sunsetStart) },
      { name: "Sunset", start: new Date(times.sunsetStart), end: new Date(times.sunset) },
      { name: "Dusk", start: new Date(times.sunset), end: new Date(times.dusk) },
      { name: "Dusk", start: new Date(times.dusk), end: new Date(times.nauticalDusk) },
      { name: "Dusk", start: new Date(times.nauticalDusk), end: new Date(times.night) }
    ]

    const sunrise = new Date(times.nightEnd)
    const sunset = new Date(times.night)
    const dayPercent = dateObj > sunrise && dateObj < sunset ? (dateObj - sunrise) / (sunset - sunrise) : 0

    for (let i = 0; i < periods.length; i++) {
      const p = periods[i]
      if (dateObj >= p.start && dateObj < p.end) {
        const percent = (dateObj - p.start) / (p.end - p.start)
        return {
          period: p.name,
          periodIndex: i,
          periodPercent: Math.min(Math.max(percent, 0), 1),
          dayPercent: dayPercent
        }
      }
    }
    return { period: "Night", periodIndex: 0, periodPercent: 0, dayPercent: dayPercent }
  }

  function getSkyArcPosition(date, isSun) {
    if (!location) return null
    const lat = location.latitude
    const lon = location.longitude
    const pos = isSun ? SunCalc.getPosition(date, lat, lon) : SunCalc.getMoonPosition(date, lat, lon)
    const sunIsNorth = getSunDeclination(date) > lat
    const transitAzimuth = sunIsNorth ? 0 : Math.PI
    let h = (((pos.azimuth - transitAzimuth) / (2 * Math.PI)) + 1) % 1
    h = Math.max(0, Math.min(1, h))
    let v = Math.sin(pos.altitude)
    v = Math.max(-1, Math.min(1, v))
    return { h, v }
  }

  function weatherIcon(code, isDay) {
    return ((isDay !== false) ? _dayIcons : _nightIcons)[String(code)] || "cloud"
  }
  function weatherCondition(code) { return _conditions[String(code)] || "Unknown" }
  function _useF() { return (typeof SettingsData !== "undefined") ? (SettingsData.useFahrenheit ?? false) : false }
  function currentTempText() {
    if (!weather.available) return "--"
    return (_useF() ? weather.tempF : weather.temp) + (_useF() ? "°F" : "°C")
  }
  function formatTemp(c) {
    if (c == null) return "--"
    return (_useF() ? Math.round(c*9/5+32) : Math.round(c)) + "°" + (_useF() ? "F" : "C")
  }
  function formatPercent(v) { return v != null ? v + "%" : "--" }
  function formatSpeed(kmh) { return kmh != null ? Math.round(kmh) + " km/h" : "--" }
  function formatPressure(hpa) { return hpa != null ? Math.round(hpa) + " hPa" : "--" }
  function calendarDayDifference(a, b) {
    return Math.floor((Date.UTC(b.getFullYear(),b.getMonth(),b.getDate()) -
      Date.UTC(a.getFullYear(),a.getMonth(),a.getDate())) / 86400000)
  }
  function calendarHourDifference(a, b) {
    return Math.floor((Date.UTC(b.getFullYear(),b.getMonth(),b.getDate(),b.getHours()) -
      Date.UTC(a.getFullYear(),a.getMonth(),a.getDate(),a.getHours())) / 3600000)
  }
  function addRef()    { refCount++; if (refCount===1 && !weather.available) updateLocation() }
  function removeRef() { refCount = Math.max(0, refCount-1) }
  function forceRefresh() { lastFetchTime = 0; fetchWeather() }

  function updateLocation() {
    const coords = (typeof SettingsData!=="undefined") ? (SettingsData.weatherCoordinates||"") : ""
    const city   = (typeof SettingsData!=="undefined") ? (SettingsData.weatherLocation||"")   : ""
    if (coords) {
      const p = coords.split(",")
      if (p.length===2) {
        const lat = parseFloat(p[0]), lon = parseFloat(p[1])
        if (!isNaN(lat) && !isNaN(lon)) {
          root.location = {city: city||"Local Weather", country:"", latitude:lat, longitude:lon}
          fetchWeather(lat, lon); return
        }
      }
    }
    if (city) { geocodeCity(city); return }
    ipFetcher.running = true
  }

  function geocodeCity(city) {
    geocodeFetcher.command = ["curl","-sf","--max-time","10",
      "https://geocoding-api.open-meteo.com/v1/search?name="+encodeURIComponent(city)+"&count=1&language=en&format=json"]
    geocodeFetcher.running = true
  }

  function fetchWeather(lat, lon) {
    if (refCount===0) return
    if (lat==null) {
      if (!location) { updateLocation(); return }
      lat = location.latitude; lon = location.longitude
    }
    const now = Date.now()
    if (now-lastFetchTime < _minFetchInterval || weatherFetcher.running) return
    const params = [
      "latitude="+lat,"longitude="+lon,
      "current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,surface_pressure,wind_speed_10m",
      "daily=sunrise,sunset,temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max",
      "hourly=temperature_2m,weather_code,precipitation_probability,wind_speed_10m,apparent_temperature,relative_humidity_2m,surface_pressure,visibility",
      "timezone=auto","forecast_days=7"
    ]
    lastFetchTime = now
    root.weather = Object.assign({}, root.weather, {loading:true})
    weatherFetcher.command = ["curl","-sf","--max-time","15","https://api.open-meteo.com/v1/forecast?"+params.join("&")]
    weatherFetcher.running = true
  }

  function _fmtDay(iso, i) {
    if (i===0) return "Today"
    if (i===1) return "Tomorrow"
    const d = new Date(); d.setDate(d.getDate()+i)
    return ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][d.getDay()]
  }
  function _fmtTime(iso) {
    if (!iso) return "--"
    try {
      const d = new Date(iso)
      return d.getHours().toString().padStart(2,"0")+":"+d.getMinutes().toString().padStart(2,"0")
    } catch(e) { return "--" }
  }

  Process {
    id: ipFetcher; running: false
    command: ["curl","-sf","--max-time","8","http://ip-api.com/json/"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const d = JSON.parse(text.trim())
          if (d.status==="fail") throw new Error("IP lookup failed")
          root.location = {city:d.city||"Local Weather",country:d.country||"",
            latitude:parseFloat(d.lat),longitude:parseFloat(d.lon)}
          root.fetchWeather(root.location.latitude, root.location.longitude)
        } catch(e) { root.lastFetchError = "IP location failed: "+String(e) }
      }
    }
  }

  Process {
    id: geocodeFetcher; running: false
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const d = JSON.parse(text.trim())
          const r = (d.results||[])[0]
          if (!r) throw new Error("No geocoding results")
          root.location = {city:r.name, country:r.country||"", latitude:r.latitude, longitude:r.longitude}
          root.fetchWeather()
        } catch(e) { root.lastFetchError = "Geocoding failed: "+String(e) }
      }
    }
  }

  Process {
    id: weatherFetcher; running: false
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const data = JSON.parse(text.trim())
          if (!data.current || !data.daily) throw new Error("Missing weather fields")
          const cur = data.current, daily = data.daily, hourly = data.hourly || {}
          const tC = cur.temperature_2m||0, fC = cur.apparent_temperature||tC

          const forecast = (daily.time||[]).map(function(t,i) {
            return {
              day: root._fmtDay(t,i), wCode: daily.weather_code?.[i]||0,
              tempMin: Math.round(daily.temperature_2m_min?.[i]||0),
              tempMax: Math.round(daily.temperature_2m_max?.[i]||0),
              tempMinF: Math.round((daily.temperature_2m_min?.[i]||0)*9/5+32),
              tempMaxF: Math.round((daily.temperature_2m_max?.[i]||0)*9/5+32),
              precipitationProbability: Math.round(daily.precipitation_probability_max?.[i]||0),
              sunrise: daily.sunrise?.[i] ? root._fmtTime(daily.sunrise[i]) : "",
              sunset:  daily.sunset?.[i]  ? root._fmtTime(daily.sunset[i])  : "",
              rawSunrise: daily.sunrise?.[i]||"", rawSunset: daily.sunset?.[i]||""
            }
          })

          const hourlyForecast = (hourly.time||[]).map(function(ht,i) {
            const di = Math.floor(i/24)
            const sr = new Date(daily.sunrise?.[di]||"")
            const ss = new Date(daily.sunset?.[di]||"")
            const t = new Date(ht)
            const hC = hourly.temperature_2m?.[i]||0
            return {
              time: root._fmtTime(ht), rawTime: ht,
              temp: Math.round(hC), tempF: Math.round(hC*9/5+32),
              feelsLike: Math.round(hourly.apparent_temperature?.[i]||hC),
              feelsLikeF: Math.round((hourly.apparent_temperature?.[i]||hC)*9/5+32),
              wCode: hourly.weather_code?.[i]||0,
              humidity: Math.round(hourly.relative_humidity_2m?.[i]||0),
              wind: Math.round(hourly.wind_speed_10m?.[i]||0),
              pressure: Math.round(hourly.surface_pressure?.[i]||0),
              precipitationProbability: Math.round(hourly.precipitation_probability?.[i]||0),
              isDay: sr<t && t<ss
            }
          })

          root.lastFetchError = ""; root.retryAttempts = 0
          root.weather = {
            available:true, loading:false,
            temp:Math.round(tC), tempF:Math.round(tC*9/5+32),
            feelsLike:Math.round(fC), feelsLikeF:Math.round(fC*9/5+32),
            city:root.location?.city||"", country:root.location?.country||"",
            wCode:cur.weather_code||0,
            humidity:Math.round(cur.relative_humidity_2m||0),
            wind:Math.round(cur.wind_speed_10m||0),
            sunrise: daily.sunrise?.[0] ? root._fmtTime(daily.sunrise[0]) : "06:00",
            sunset:  daily.sunset?.[0]  ? root._fmtTime(daily.sunset[0])  : "18:00",
            rawSunrise: daily.sunrise?.[0]||"", rawSunset: daily.sunset?.[0]||"",
            pressure:Math.round(cur.surface_pressure||0),
            precipitationProbability:Math.round(daily.precipitation_probability_max?.[0]||0),
            isDay:Boolean(cur.is_day),
            forecast:forecast, hourlyForecast:hourlyForecast
          }
        } catch(e) {
          root.weather = Object.assign({}, root.weather, {loading:false})
          root.lastFetchError = String(e)
          root.retryAttempts++
          if (root.retryAttempts < 3) retryTimer.restart()
        }
      }
    }
  }

  Timer { id:pollTimer; interval:900000; running:root.refCount>0; repeat:true; triggeredOnStart:true; onTriggered:root.fetchWeather() }
  Timer { id:retryTimer; interval:30000; running:false; repeat:false; onTriggered:root.fetchWeather() }

  Component.onCompleted: {
    if (typeof SettingsData !== "undefined") {
      SettingsData.weatherLocationChanged.connect(function() {
        root.location=null; root.lastFetchTime=0
        if (root.refCount>0) root.updateLocation()
      })
      SettingsData.weatherCoordinatesChanged.connect(function() {
        root.location=null; root.lastFetchTime=0
        if (root.refCount>0) root.updateLocation()
      })
    }
  }
}
