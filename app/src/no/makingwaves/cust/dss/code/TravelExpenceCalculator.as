package no.makingwaves.cust.dss.code
{
	import mx.collections.ArrayCollection;
	
	import no.makingwaves.cust.dss.model.ModelLocator;
	import no.makingwaves.cust.dss.vo.CarSpecificationVO;
	import no.makingwaves.cust.dss.vo.MotorboatSpecificationVO;
	import no.makingwaves.cust.dss.vo.MotorcycleSpecificationVO;
	import no.makingwaves.cust.dss.vo.OtherSpecificationVO;
	import no.makingwaves.cust.dss.vo.RateVO;
	import no.makingwaves.cust.dss.vo.TravelAccomodationVO;
	import no.makingwaves.cust.dss.vo.TravelAdvanceVO;
	import no.makingwaves.cust.dss.vo.TravelDeductionVO;
	import no.makingwaves.cust.dss.vo.TravelOutlayVO;
	import no.makingwaves.cust.dss.vo.TravelRateInternationalVO;
	import no.makingwaves.cust.dss.vo.TravelRateRuleVO;
	import no.makingwaves.cust.dss.vo.TravelSpecificationVO;
	import no.makingwaves.cust.dss.vo.TravelVO;
	import no.makingwaves.util.Util;
	import no.makingwaves.util.date.DateRanger;
	
	public class TravelExpenceCalculator
	{
		[Bindable]
		public var totalExpense : Number = 0.0;
		
		public function TravelExpenceCalculator() {
		}
		
		// kalkuler alle kostnader ===========================================================
		public function calculate():Number {
			var totAmount : Number = 0.0;
			totAmount += calculateAllowances();
			totAmount += calculateSpecifications();
			totAmount += calculateAccomodations();
			totAmount += calculateDeductions();
			totAmount += calculateOutlays();
			totAmount += calculateTraveladvances();
			this.totalExpense = totAmount;
			// update allowances-model
			ModelLocator.getInstance().travelAllowance.netamount = Number(totAmount.toFixed(2));
			
			return totalExpense;
		}
		
		// kalkuler kostgodtgjørelse =========================================================
		public function calculateAllowances():Number {
			var amount:Number = 0.0;
			var rateRule:TravelRateRuleVO;
			var ratePercent:Number = 0;
			var travelInfo:TravelVO = ModelLocator.getInstance().activeTravel;
			var travelDateInfo:DateRanger = ModelLocator.getInstance().travelLength;
			var days:Number = 1;
			var dailyAllowance:Number;
			
			// domestic or international travel
			if (travelInfo.travel_type == travelInfo.DOMESTIC) {
				// DOMESTIC TRAVEL
				rateRule = this.getAllowanceRate(travelInfo, travelDateInfo);
				dailyAllowance = Number(rateRule.cost.toFixed(2));
				// if travel is over more than a day
				if (travelDateInfo.total_hours > 24) {
					days = travelDateInfo.days;
					// for travels over 24 hours, 6 hours or more into a new 24-hour period counts as one 24-hour.
					if (travelDateInfo.hours >= 6) {
						days++;
					}
				}								
				// sum up total allowance for this domestic travel
				var allowance_28days:Number = 0;
				if (days <= 28) {
					amount += Number((dailyAllowance * days).toFixed(2));
				} else {
					amount += Number((dailyAllowance * 28).toFixed(2));
					allowance_28days = Number(((dailyAllowance*0.75) * (days-28)).toFixed(2));
					amount += allowance_28days;
				}
				
				// update travelallowance
				ModelLocator.getInstance().travelAllowance.domestic = true;
				var allowance:RateVO = new RateVO();
				allowance.num = (days <= 28) ? travelDateInfo.total_hours : (28*24); //days;
				allowance.rate = dailyAllowance;
				allowance.amount = amount;
				ModelLocator.getInstance().travelAllowance.allowance = allowance;
				if (allowance_28days > 0) {
					var allowance28:RateVO = new RateVO();
					allowance28.num = travelDateInfo.total_hours - (28*24);//days - 28;
					allowance28.rate = dailyAllowance * 0.75;
					allowance28.amount = allowance28.num * allowance28.rate;
					ModelLocator.getInstance().travelAllowance.allowance_28days = allowance28;
				}
								
			} else {
				// INTERNATIONAL TRAVEL
				rateRule = this.getAllowanceRate(travelInfo, travelDateInfo);
				// search and find destinations and period of time on this/these destinations
				amount += calculateInternationalAllowance(rateRule);
				
			}
			
			/* removed until further notice
			// search and add amounts for admin. allowances
			var adminNum:Number = 0;
			var deductionList:ArrayCollection = ModelLocator.getInstance().travelDeductionList;
			for (var i:Number = 0; i < deductionList.length; i++) {
				var deduction:TravelDeductionVO = TravelDeductionVO(deductionList.getItemAt(i));
				if (deduction.breakfast && deduction.lunch && deduction.dinner) {
					// all meals are deducted - admin allowance is added
					adminNum++;
				}
			}
			if (adminNum > 0) {
				var admin_allowance:RateVO = new RateVO();
				admin_allowance.num = adminNum;
				admin_allowance.rate = this.getRate("redraw_extra").cost;
				admin_allowance.amount = admin_allowance.num * admin_allowance.rate;
				ModelLocator.getInstance().travelAllowance.adm_allowance = admin_allowance;
				
				amount += admin_allowance.amount;
			}
			*/
			
			return amount;
		}
		
		private function calculateInternationalAllowance(rateRule:TravelRateRuleVO, date:Date=null):Number {
			var amount:Number = 0.0;
			var days:Number = 1;
			var dailyAllowance:Number;
			var intRate:TravelRateInternationalVO;
			var prevIntRate:TravelRateInternationalVO;
			var specificationList:ArrayCollection = ModelLocator.getInstance().travelSpecsList;
			var startDistance:TravelSpecificationVO;
			var endDistance:TravelSpecificationVO;
			var nextDistance:TravelSpecificationVO;
			var allowancesInternational:ArrayCollection = new ArrayCollection();
			var allowancesOver28days:RateVO = new RateVO();
			
			// get travel length and add one day if last day exceeds 6 hours
			var travelPeriode:DateRanger = ModelLocator.getInstance().travelLength;
			var num24hours:Number = travelPeriode.total_24hours;
			if (num24hours > 0 && travelPeriode.hours >= 6) { num24hours++; }
			
			if (travelPeriode.total_min != 0) {
				// set start date and first periode
				var msPerDay:int = 1000 * 60 * 60 * 24;
				var msPerHour:int = 1000 * 60 * 60;
				var timeStart:String = ModelLocator.getInstance().activeTravel.travel_time_out;
				var dateStart:Date = new Date();
				dateStart.setTime(ModelLocator.getInstance().activeTravel.travel_date_out.getTime());
				dateStart.setHours(timeStart.substr(0,2), timeStart.substr(2,2));
				var dateStop:Date = new Date();
				dateStop.setTime(dateStart.getTime() + msPerDay);
				// set dates to UTC-time
				var timezoneDefault:Number = new Date().timezoneOffset / 60;
				dateStart.setTime(dateStart.getTime() + (timezoneDefault*msPerHour));
				dateStop.setTime(dateStop.getTime() + (timezoneDefault*msPerHour));
				
				var lastLocationObject:Object;
				var daysCalculated:int = 0;
				// for each 24-hour day, check which international rate that should be used
				for (var i:int=0; i < num24hours; i++) {
					//trace("check between " + Util.formatDate(dateStart) + " - " + Util.formatDate(dateStop));
					var timeFrameSpecs:ArrayCollection = new ArrayCollection();
					// get spesifications within current timeframe
					for (var s:int = 0; s < specificationList.length; s++) {
						var spec:TravelSpecificationVO = specificationList.getItemAt(s) as TravelSpecificationVO;
						var fromDate:Date = new Date();
						var toDate:Date = new Date()
						fromDate.setTime(spec.from_date.getTime() + (spec.from_timezone*msPerHour));
						toDate.setTime(spec.to_date.getTime() + (spec.to_timezone*msPerHour));
						
						if (fromDate >= dateStart && fromDate < dateStop) {
							timeFrameSpecs.addItem(spec);
							//trace("-> in timeframe: " + spec.from_destination + ", " + spec.from_country);
						} else if (toDate >= dateStart && toDate <= dateStop) {
							//trace("-> in timeframe: " + spec.from_destination + ", " + spec.from_country);
							timeFrameSpecs.addItem(spec);
						}
					}
					// get each country timeframe based on specs between timeframe
					var activeLocation:Object = null;
					var locationList:ArrayCollection = new ArrayCollection();
					var specStartDate:Date = new Date();
					var specStopDate:Date = new Date();
					for (var t:int = 0; t < timeFrameSpecs.length; t++) {
						var spec:TravelSpecificationVO = timeFrameSpecs.getItemAt(t) as TravelSpecificationVO;
						var testTravelEnd:Boolean = true;
						if (activeLocation == null) {
							activeLocation = null;
							activeLocation = new Object();
							activeLocation.country = spec.from_country;
							activeLocation.city = (spec.from_city == "-") ? "" : spec.from_city;
							specStartDate.setTime(spec.from_date.getTime() - (spec.from_timezone*msPerHour));
							activeLocation.startDate = (specStartDate.getTime() > dateStart.getTime()) ? specStartDate : dateStart;
							
						} else {
							if (activeLocation.country != spec.from_country || activeLocation.city != spec.from_city) {
								specStopDate.setTime(spec.to_date.getTime() - (spec.to_timezone*msPerHour));
								activeLocation.stopDate = (specStopDate.getTime() < dateStop.getTime()) ? specStopDate : dateStop;;
								locationList.addItem(activeLocation);
								//trace(" -> location added: " + activeLocation.country + ", " + activeLocation.city);
								specStartDate = new Date();
								specStopDate = new Date();
								activeLocation = null;
								activeLocation = new Object();
								activeLocation.country = spec.from_country;
								activeLocation.city = (spec.from_city == "-") ? "" : spec.from_city;;
								specStartDate.setTime(spec.from_date.getTime() - (spec.from_timezone*msPerHour));
								activeLocation.startDate = (specStartDate.getTime() > dateStart.getTime()) ? specStartDate : dateStart;
								
							} else if (activeLocation.country != spec.to_country || activeLocation.city != spec.to_city) {
								specStopDate.setTime(spec.to_date.getTime() - (spec.to_timezone*msPerHour));
								activeLocation.stopDate = (specStopDate.getTime() < dateStop.getTime()) ? specStopDate : dateStop;
								locationList.addItem(activeLocation);
								//trace(" -> location added: " + activeLocation.country + ", " + activeLocation.city);
								specStartDate = new Date();
								specStopDate = new Date();
								activeLocation = null;
								activeLocation = new Object();
								activeLocation.country = spec.to_country;
								activeLocation.city = (spec.to_city == "-") ? "" : spec.to_city;
								specStartDate.setTime(spec.from_date.getTime() - (spec.from_timezone*msPerHour));
								activeLocation.startDate = (specStartDate.getTime() > dateStart.getTime()) ? specStartDate : dateStart;
								testTravelEnd = false;
								
							}
						}
						if ((activeLocation != null && testTravelEnd && (spec.from_country != spec.to_country || spec.from_city != spec.to_city)) ||
						    (activeLocation != null && t == (timeFrameSpecs.length-1))) {
							// current country rate has reached its end - register it
							specStopDate.setTime(spec.to_date.getTime() - (spec.to_timezone*msPerHour));
							activeLocation.stopDate = (specStopDate.getTime() < dateStop.getTime()) ? specStopDate : dateStop;
							locationList.addItem(activeLocation);
							if (t != (timeFrameSpecs.length)) {
								if (specStopDate.getTime() < dateStop.getTime()) {
									activeLocation = new Object();
									activeLocation.country = spec.to_country;
									activeLocation.city = (spec.to_city == "-") ? "" : spec.to_city;
									activeLocation.startDate = specStopDate;
									activeLocation.stopDate = dateStop;
									locationList.addItem(activeLocation);
								}														
							}								
							
							
							//trace(" -> location added: " + activeLocation.country + ", " + activeLocation.city);
							specStartDate = new Date();
							specStopDate = new Date();
							activeLocation = null;
						}
					}
					// find the correct country/city based on the longest timeframe
					var maxTimeframe:Number = 0;
					var maxTimeframeObject:Object;
					if (locationList.length == 0 || (i+1) == num24hours) {
						// no specification in this timeframe, use last visited country
						maxTimeframeObject = lastLocationObject;
					} else {
						for (var l:int=0; l < locationList.length; l++) {
							var ranger:DateRanger = new DateRanger();
							ranger.getDateRange(locationList.getItemAt(l).startDate, locationList.getItemAt(l).stopDate);
							if (ranger.total_min > maxTimeframe) {
								maxTimeframe = ranger.total_min;
								maxTimeframeObject = locationList.getItemAt(l);
							}
						}
					}
					// get the rate
					intRate = this.getInternationalRate(maxTimeframeObject.country, maxTimeframeObject.city);
					if (intRate == null) {
						// active 'rate' is in home country - find domestic rate 
						intRate = new TravelRateInternationalVO();
						var travelInfo:DateRanger = ModelLocator.getInstance().travelLength;
						var localRate:TravelRateRuleVO;
						if (travelInfo.total_min > 12) {
							localRate = getRate("allowance_04"); 
						} else {
							localRate = getRate("allowance_03");
						}
						intRate.country = maxTimeframeObject.country;
						intRate.city = maxTimeframeObject.city;
						intRate.allowance = localRate.cost;
					}
					dailyAllowance = Number(((intRate.allowance * rateRule.percent) / 100).toFixed(2));
					daysCalculated++;
					
					if (daysCalculated > 28) {
						// calculation for over 28 days - reduce allowance with 25%
						dailyAllowance = Number((dailyAllowance*0.75).toFixed(2));
					}
					trace("Allowance for day " + daysCalculated + ": " + Util.formatDate(dateStart) + "-" + Util.formatDate(dateStop) + ": " + dailyAllowance + ",- (" + maxTimeframeObject.country + ", " + maxTimeframeObject.city + ")");
					
					if (date != null) {
						// if date is specified in method - return only value for this date
						if (Util.formatDate(date) == Util.formatDate(dateStart)) {
							return dailyAllowance;
						}
					}
					
					// add/update to the allowance model
					var added:Boolean = false;
					if (daysCalculated > 28) {
						// calculation for over 28 days
						allowancesOver28days.num = daysCalculated - 28;
						allowancesOver28days.rate = dailyAllowance;
						allowancesOver28days.amount += dailyAllowance;
						
					} else {
						// normal calculation
						for (var m:int=0; m < allowancesInternational.length; m++) {
							var allInt:RateVO = allowancesInternational.getItemAt(m) as RateVO;
							if (allInt.rate == dailyAllowance) {
								allInt.num++;
								allInt.amount = Number((allInt.rate * allInt.num).toFixed(2));
								added = true;
								break;
							}
						}
						if (!added) {
							var allowance:RateVO = new RateVO();
							allowance.rate = dailyAllowance;
							allowance.num = 1;
							allowance.amount = dailyAllowance;
							allowancesInternational.addItem(allowance);
						}
					}
					
					// get ready to find rates for the next 24-hour day
					dateStart.setTime(dateStop.getTime());
					dateStop.setTime(dateStart.getTime() + msPerDay);
					if (locationList.length > 0) {
						lastLocationObject = locationList.getItemAt(locationList.length-1);
					}
				}
	
				// update allowance model if this is not a 'date only' calculation
				if (date == null) {
					ModelLocator.getInstance().travelAllowance.allowance_international = allowancesInternational;
					ModelLocator.getInstance().travelAllowance.allowance_28days = allowancesOver28days;					
				}
				
				// calculate amount
				for (var a:int = 0; a < allowancesInternational.length; a++) {
					amount += RateVO(allowancesInternational.getItemAt(a)).amount;
					amount += allowancesOver28days.amount;
				}
			}
			
			return amount;
		}
		
		/* BACKUP of calculateInternationalAllowance from 08.10.2008 /*
		private function calculateInternationalAllowance(rateRule:TravelRateRuleVO, date:Date=null):Number {
			var amount:Number = 0.0;
			var days:Number = 1;
			var dailyAllowance:Number;
			var intRate:TravelRateInternationalVO;
			var prevIntRate:TravelRateInternationalVO;
			var specificationList:ArrayCollection = ModelLocator.getInstance().travelSpecsList;
			var startDistance:TravelSpecificationVO;
			var endDistance:TravelSpecificationVO;
			var nextDistance:TravelSpecificationVO;
			var allowancesInternational:ArrayCollection = new ArrayCollection();
			// update travelallowance
			ModelLocator.getInstance().travelAllowance.domestic = false;
			// search through all specifications to find allowance parameters
			for (var i:Number = 0; i < specificationList.length; i++) {
				var traveldistance:TravelSpecificationVO = TravelSpecificationVO(specificationList.getItemAt(i));
				if (traveldistance.is_travel_start && startDistance == null) {
					startDistance = traveldistance;
				} 
				if (startDistance != null && traveldistance.is_travel_end) {
					endDistance = traveldistance;
					
				} 
				if (startDistance != null && endDistance != null && nextDistance == null) {
					if (i == specificationList.length-1) {
						nextDistance = traveldistance;
					} else {		
						nextDistance = TravelSpecificationVO(specificationList.getItemAt(i+1));;
					}					
				} 
				
				if (nextDistance != null) {
					// a complete distance has been found - start calculating cost for this distance
					
					// find correct rate for this distance
					intRate = this.getInternationalRate(endDistance.to_country, endDistance.to_city);
					if (intRate != null) {
						prevIntRate = intRate;						
					} else if (intRate == null && prevIntRate != null) {
						intRate = prevIntRate;
					} else if (intRate == null && prevIntRate == null) {
						// travel distance is not filled in properly or is not a international travel
						intRate = new TravelRateInternationalVO();
					}
					dailyAllowance = Number(((intRate.allowance * rateRule.percent) / 100).toFixed(2));					
					
					// find how long period of time this travel distance took
					var distanceRange:DateRanger = new DateRanger();
					var endDate:Date = (nextDistance.from_date != null) ? nextDistance.from_date : nextDistance.to_date;
					distanceRange.getDateRange(startDistance.from_date, endDate);
					// if travel is over more than a day
					days = distanceRange.days;
					if (distanceRange.total_hours > 24) {
						// for travels over 24 hours, 6 hours or more into a new 24-hour period counts as one 24-hour.
						if (distanceRange.hours >= 6) {	
							days++;
						}
					}
					
					// calculate allowance for this distance
					if (date == null) {
						var allowance:RateVO = new RateVO();
						allowance.rate = dailyAllowance;
						if (days > 0) {
							amount += Number((dailyAllowance * days).toFixed(2));
							// add to model reference array
							allowance.num = days;
							allowance.amount = Number((dailyAllowance * days).toFixed(2));
							allowancesInternational.addItem(allowance);
						} else {
							// calculate international day trip, no accomodation
							amount += Number(dailyAllowance.toFixed(2));
							allowance.num = distanceRange.total_hours;
							allowance.amount = Number((dailyAllowance * 1).toFixed(2));
							ModelLocator.getInstance().travelAllowance.allowance = allowance;
						}
						
					} else {
						// if date is defined, only daily allowance for this date should be returned
						if (date >= startDistance.from_date && date <= endDate) {
							return dailyAllowance;
						}
					}
					
					// reset distance to search for another
					startDistance = null;
					endDistance = null;
					nextDistance = null;
				}
			}

			// update allowance model
			ModelLocator.getInstance().travelAllowance.allowance_international = allowancesInternational;
			
			return amount;
		}
		*/
		
		private function getAllowanceRate(travelInfo:TravelVO, travelDateInfo:DateRanger):TravelRateRuleVO {
			var rateName:String = "allowance";
			if (travelInfo.travel_type == travelInfo.DOMESTIC) {
				// DOMESTIC TRAVEL
				if (travelDateInfo.total_hours >= 12) {
					// travel longer than 12 hours
					rateName += "_04";
					
				} else if (travelDateInfo.total_hours >= 9 && travelDateInfo.total_hours < 12) {
					// travel periode between 9 and 12 hours
					rateName += "_03";
					
				} else if (travelDateInfo.total_hours >= 5 && travelDateInfo.total_hours < 9) {
					// travel periode between 5 and 9 hours
					rateName += "_02";
					
				} else if (travelDateInfo.total_hours < 5) {
					// travel time less than 5 hours
					rateName += "_01";
				}
				
			} else {
				// INTERNATIONAL TRAVEL
				if (travelDateInfo.total_hours >= 6 && travelDateInfo.total_hours < 12) {
					// travel longer than 12 hours
					rateName += "_05";
			
				} else if (travelDateInfo.total_hours >= 12) {
					// travel periode between 5 and 9 hours
					rateName += "_06";
				}
			}
			return getRate(rateName);
		}
		
		public function getDailyAllowance(date:Date):Number {
			var amount:Number = 0.0;
			var travelInfo:TravelVO = ModelLocator.getInstance().activeTravel;
			var travelDateInfo:DateRanger = ModelLocator.getInstance().travelLength;
			
			if (travelInfo.travel_type == travelInfo.DOMESTIC) {
				// domestic travel, calculate daily allowance based on travellength and totalt allowance
				var days:Number = 1;
				var totaltAllowance:Number = this.calculateAllowances();
				// if travel is over more than a day
				if (travelDateInfo.total_hours > 24) {
					days = travelDateInfo.days;
					// for travels over 24 hours, 6 hours or more into a new 24-hour period counts as one 24-hour.
					if (travelDateInfo.hours >= 6) { days++; }
				}
				amount = totaltAllowance / days;
				
			} else {
				// internation travel, calculation must check period of time and location
				var rateRule:TravelRateRuleVO = this.getAllowanceRate(travelInfo, travelDateInfo);
				amount = this.calculateInternationalAllowance(rateRule, date);
			}
			
			return amount;
		}
		
		// kalkuler reisespesifikasjoner og reiseutlegg ======================================
		public function calculateSpecifications():Number {
			var amount:Number = 0.0;
			var specificationList:ArrayCollection = ModelLocator.getInstance().travelSpecsList;
			for (var i:Number = 0; i < specificationList.length; i++) {
				amount += calculateSpecification(TravelSpecificationVO(specificationList.getItemAt(i)));
			}
			
			// update allowance parameters for car specifications
			calculateCarAllowances();
			
			return amount;
		}
		
		public function calculateSpecification(specification:TravelSpecificationVO):Number {
			var cost:Number = 0.0;
			var type:String = (specification.specification != null) ? specification.specification.type : "ticket";
			switch(type) {
				case "car":
				case "motorcycle":
				case "motorboat":
				case "other":
					cost = calculateOwnVehicle(specification);
					break;
				case "ticket":
					cost = Number(specification.cost.getCost());
					break;
			}
			
			return cost;
		}
		
		private function calculateOwnVehicle(specification:TravelSpecificationVO):Number {
			var cost:Number = 0.0;
			var distance:Number;
			var rateRule:TravelRateRuleVO;
			var passengerGeneralRate:TravelRateRuleVO = getRate("transport_passenger_extra_01");
			var rateRuleName:String = "transport_";
			// find correct rate rule
			switch(specification.specification.type) {
				case "other":
					var otherSpec:OtherSpecificationVO = OtherSpecificationVO(specification.specification);
					switch(otherSpec.other_type) {
						case otherSpec.TYPE_EL_CAR:
							rateRuleName += "el-car_01"; break;
						case otherSpec.TYPE_SNOWMOBILE:
							rateRuleName += "snowmobile_01"; break;
						case otherSpec.TYPE_OTHER:
							rateRuleName += "other_01"; break;
					}
					distance = otherSpec.distance;
					break;
						
				default:
					rateRuleName += specification.specification.type;
					break;
			}
			
			if (specification.specification.type == "car") {
				var detailsCar:CarSpecificationVO = CarSpecificationVO(specification.specification);
				distance = detailsCar.distance;
				if (detailsCar.distance_calender == detailsCar.TYPE_ABOVE_9000KM) {
					rateRuleName += "_02";
				} else if (detailsCar.distance_calender == detailsCar.TYPE_BELOW_9000KM) {
					rateRuleName += "_01";
				}
				
				// check for additional car rates
				if (detailsCar.additional_workplace) {
					var workplaceRate:TravelRateRuleVO = getRate("transport_car_extra_01");
					cost += distance * workplaceRate.cost;
				}
				if (detailsCar.passengers > 0) {
					var passengerRate:TravelRateRuleVO = getRate("transport_car_extra_02");
					cost += (distance * passengerRate.cost) * detailsCar.passengers;
				}
				if (detailsCar.additional_trailer) {
					var trailerRate:TravelRateRuleVO = getRate("transport_car_extra_03");
					cost += distance * trailerRate.cost;
				}
				if (detailsCar.distance_forestroad > 0) {
					var forrestRate:TravelRateRuleVO = getRate("transport_car_extra_04");
					cost += detailsCar.distance * forrestRate.cost;
				}
					
			} else if (specification.specification.type == "motorcycle") {
				var detailsMotorcycle:MotorcycleSpecificationVO = MotorcycleSpecificationVO(specification.specification);
				distance = detailsMotorcycle.distance;
				if (detailsMotorcycle.motorcycle_type == detailsMotorcycle.TYPE_ABOVE_125CC) {
					rateRuleName += "_01";
				} else if (detailsMotorcycle.motorcycle_type == detailsMotorcycle.TYPE_BELOW_125CC) {
					rateRuleName += "_02";
				}
				
				// check for additional transport rates
				if (detailsMotorcycle.passengers > 0) {
					cost += (distance * passengerGeneralRate.cost) * detailsMotorcycle.passengers;
				}
				
			} else if (specification.specification.type == "motorboat") {
				var detailsMotorboat:MotorboatSpecificationVO = MotorboatSpecificationVO(specification.specification);
				distance = detailsMotorboat.distance;
				if (detailsMotorboat.motorboat_type == detailsMotorboat.TYPE_ABOVE_50HK) {
					rateRuleName += "_01";
				} else if (detailsMotorboat.motorboat_type == detailsMotorboat.TYPE_BELOW_50HK) {
					rateRuleName += "_02";
				}
				
				// check for additional transport rates
				if (detailsMotorboat.passengers > 0) {
					cost += (distance * passengerGeneralRate.cost) * detailsMotorboat.passengers;
				}
				
			}
			// calculate main rate
			rateRule = this.getRate(rateRuleName);
			cost += distance * rateRule.cost;
			/*
			if (specification.specification.type == "car") {
				// update specification with correct rate
				detailsCar.rate = rateRule.cost;
				detailsCar.cost.cost = rateRule.cost * detailsCar.distance; 
			}
			*/
			// main specification update
			specification.cost.cost = cost;
			specification.cost.cost_currency_rate = 1;
			specification.cost.update();
			
			return cost;
		}
		
		private function calculateCarAllowances():void {
			// init calculation variables
			var car_distance1:RateVO = new RateVO();	// below 9000 km
			var car_distance2:RateVO = new RateVO();	// above 9000 km
			var car_passengers:RateVO = new RateVO();
			var car_otherrates:RateVO = new RateVO();
			car_distance1.init();
			car_distance2.init();
			car_passengers.init();
			car_otherrates.init();
			
			// collect needed rates
			var passengerGeneralRate:TravelRateRuleVO = getRate("transport_passenger_extra_01");
			var distanceBelow9000:TravelRateRuleVO = getRate("transport_car_01");
			var distanceAbove9000:TravelRateRuleVO = getRate("transport_car_02");
			
			// start calculation
			var specificationList:ArrayCollection = ModelLocator.getInstance().travelSpecsList;
			for (var i:Number = 0; i < specificationList.length; i++) {
				var travelSpec:TravelSpecificationVO = TravelSpecificationVO(specificationList.getItemAt(i));
				var type:String = (travelSpec.specification != null) ? travelSpec.specification.type : "";
				if (type == "car") {
					var detailsCar:CarSpecificationVO = CarSpecificationVO(travelSpec.specification);
					if (detailsCar.distance_calender == detailsCar.TYPE_ABOVE_9000KM) {
						car_distance2.num += detailsCar.distance;
						car_distance2.rate = distanceAbove9000.cost;
						car_distance2.amount += (car_distance2.num * car_distance2.rate);

					} else if (detailsCar.distance_calender == detailsCar.TYPE_BELOW_9000KM) {
						car_distance1.num += detailsCar.distance;
						car_distance1.rate = distanceBelow9000.cost;
						car_distance1.amount += (car_distance1.num * car_distance1.rate);
					
					}
					
					// more rates
					if (detailsCar.additional_workplace) {
						var workplaceRate:TravelRateRuleVO = getRate("transport_car_extra_01");
						car_otherrates.num += detailsCar.distance;
						car_otherrates.amount += (car_otherrates.num * workplaceRate.cost);

					}
					if (detailsCar.passengers > 0) {
						var passengerRate:TravelRateRuleVO = getRate("transport_car_extra_02");
						car_passengers.num += detailsCar.distance;
						car_passengers.rate = passengerRate.cost;
						car_passengers.amount += (car_passengers.num * car_passengers.rate);
					
					}
					if (detailsCar.additional_trailer) {
						var trailerRate:TravelRateRuleVO = getRate("transport_car_extra_03");
						car_otherrates.num += detailsCar.distance;
						car_otherrates.amount += (car_otherrates.num * trailerRate.cost);

					}
					if (detailsCar.distance_forestroad > 0) {
						var forrestRate:TravelRateRuleVO = getRate("transport_car_extra_04");
						car_otherrates.num += detailsCar.distance_forestroad;
						car_otherrates.amount += (car_otherrates.num * forrestRate.cost);

					}
				}
			}
			
			// update model
			ModelLocator.getInstance().travelAllowance.car_distance1 = car_distance1;
			ModelLocator.getInstance().travelAllowance.car_distance2 = car_distance2;
			ModelLocator.getInstance().travelAllowance.car_passengers = car_passengers;
			ModelLocator.getInstance().travelAllowance.car_otherrates = car_otherrates;
		}
		
		public function getVisitedCountries():ArrayCollection {
			var visited:ArrayCollection = new ArrayCollection();
			var specificationList:ArrayCollection = ModelLocator.getInstance().travelSpecsList;
			for (var i:Number = 0; i < specificationList.length; i++) {
				var specification:TravelSpecificationVO = TravelSpecificationVO(specificationList.getItemAt(i));
				if (specification.is_travel_end) {
					if (specification.to_country != "") {
						var country:String = specification.to_country;
						visited.addItem(country);						
					}
				}
			}
			return visited;
		}
		
		// kalkuler overnattinger ===========================================================
		public function calculateAccomodations():Number {
			var amount:Number = 0.0;
			var amount28days:Number = 0.0;
			var daysCount:Number = 0;
			var accomodationList:ArrayCollection = ModelLocator.getInstance().travelAccomodationList;
			// reset nighttarif travelallowances 
			var model:ModelLocator = ModelLocator.getInstance()
			model.travelAllowance.nighttariff_international = new ArrayCollection();
			model.travelAllowance.nighttariff_28days = new RateVO();
			model.travelAllowance.nighttariff_domestic = new RateVO();
			model.travelAllowance.nighttariff_domestic_hotel = new RateVO();
			// calculate accomodations
			for (var i:Number = 0; i < accomodationList.length; i++) {
				var accomodation:TravelAccomodationVO = TravelAccomodationVO(accomodationList.getItemAt(i));
				amount += calculateAccomodation(TravelAccomodationVO(accomodationList.getItemAt(i)), daysCount);
				// update accomodation days so far
				var distanceRange:DateRanger = new DateRanger();
				distanceRange.getDateRange(accomodation.fromdate, accomodation.todate);
				daysCount += distanceRange.days;
				
			}
			
			// update travelallowance
			if (amount > 0)				
				ModelLocator.getInstance().travelAllowance.accomodation = true;
			
			return amount;
		}
		
		public function calculateAccomodation(accomodation:TravelAccomodationVO, earlierNightsNum:Number=0):Number {
			var amount:Number = 0.0;
			var days:Number = 1;
			var dailyAllowance:Number;
			var rateRule:TravelRateRuleVO;
			var travelInfo:TravelVO = ModelLocator.getInstance().activeTravel;
			// night tariff for collecting model allowance info 
			var nighttariff:RateVO = new RateVO();
			// Authorized or unauthorized accomodation
			if (accomodation.type != accomodation.TYPE_HOTEL) {
				rateRule = this.getRate("accomodation_unauthorized");
				// accomodation unauthorized - travel by rate
				if (travelInfo.travel_type == travelInfo.DOMESTIC) {
					// domestic accomodation rules apply
					dailyAllowance = rateRule.cost;
					/*if (accomodation.type == accomodation.TYPE_UNATHORIZED_HOTEL) {
						nighttariff_domestic_hotel.rate = dailyAllowance;
					} else {
						nighttariff_domestic.rate = dailyAllowance;
					}*/					
					
				} else {
					// international accomodation rules apply
					var intRate:TravelRateInternationalVO = this.getInternationalRate(accomodation.country, accomodation.city);
					if (intRate != null) {
						// accomodation took place outside Norway
						dailyAllowance = intRate.night;
					} else {
						// accomodation took place in Norway - domestic rule apply
						dailyAllowance = rateRule.cost;
					}
				}
				
				// find how long period of time this accomodation lasted
				var distanceRange:DateRanger = new DateRanger();
				distanceRange.getDateRange(accomodation.fromdate, accomodation.todate);
				
				nighttariff.rate = dailyAllowance;
				nighttariff.num = distanceRange.days;
				nighttariff.amount = Number((dailyAllowance * distanceRange.days).toFixed(2));
							
				// calculate allowance for this distance
				var totalDays:Number = earlierNightsNum + distanceRange.days;
				if (totalDays <= 28) {
					amount += Number((dailyAllowance * distanceRange.days).toFixed(2));
					
					// update allowance model
					if (travelInfo.travel_type == travelInfo.DOMESTIC) {
						if (accomodation.type == accomodation.TYPE_UNATHORIZED_HOTEL) {
							ModelLocator.getInstance().travelAllowance.nighttariff_domestic_hotel = nighttariff;
						} else {
							ModelLocator.getInstance().travelAllowance.nighttariff_domestic = nighttariff;
						}
					} else {
						ModelLocator.getInstance().travelAllowance.nighttariff_international.addItem(nighttariff);
					}
				
				} else {
					// one or all parts of accomodation should be reduced
					if (earlierNightsNum >= 28) {
						// all days reduced
						amount += Number(((dailyAllowance * 0.75) * distanceRange.days).toFixed(2));
					} else {
						// some days reduced, some not
						var reducedDays:Number = totalDays - 28;
						var normalDays:Number = distanceRange.days - reducedDays;
						amount += Number((dailyAllowance * normalDays).toFixed(2));
						amount += Number(((dailyAllowance * 0.75) * reducedDays).toFixed(2));
					}
				}
				
				// calculate redraws for included breakfast
				/*
				if (accomodation.breakfast_inluded > 0) {
					var breakfastRatePst:Number = TravelRateRuleVO(this.getRate("redraw_04")).percent;
					var dailyRedraw:Number = (dailyAllowance * breakfastRatePst) / 100;
					amount -= Number((dailyRedraw * accomodation.breakfast_inluded).toFixed(2));
				}
				*/
				
				// main specification update
				accomodation.cost.cost = amount;
				accomodation.cost.cost_currency_rate = 1;
				accomodation.cost.update();
				
			} else {
				// accomodation authorized - travel by bill
				accomodation.actual_cost.update();
				amount += Number(accomodation.actual_cost.getCost());
			}
			
			
			return Number(amount.toFixed(2));
		}
		
		
		// kalkuler trekk ===================================================================
		public function calculateDeductions(only_deduction:TravelDeductionVO=null):Number {
			// init vars and find different rates
			var amount:Number = 0.0;
			//var days:Number = 1;
			//var travelDateInfo:DateRanger = ModelLocator.getInstance().travelLength;
			var travelInfo:TravelVO = ModelLocator.getInstance().activeTravel;
			
			var rateName:String = "redraw";
			var breakfastRate:TravelRateRuleVO;
			var lunchRate:TravelRateRuleVO;
			var dinnerRate:TravelRateRuleVO;
			var extraRate:TravelRateRuleVO;
			if (travelInfo.travel_type == travelInfo.DOMESTIC) {
				breakfastRate = this.getRate(rateName + "_01");
				lunchRate = this.getRate(rateName + "_02");
				dinnerRate = this.getRate(rateName + "_03");
			} else {
				breakfastRate = this.getRate(rateName + "_04");
				lunchRate = this.getRate(rateName + "_05");
				dinnerRate = this.getRate(rateName + "_06");
			}
			extraRate = this.getRate(rateName + "_extra");
					
			if (only_deduction == null) {	
				var deductionList:ArrayCollection = ModelLocator.getInstance().travelDeductionList;
				for (var i:Number = 0; i < deductionList.length; i++) {
					var deduction:TravelDeductionVO = TravelDeductionVO(deductionList.getItemAt(i));
					amount += this.calculateDeduction(deduction, breakfastRate, lunchRate, dinnerRate, extraRate);
				}
			} else {
				amount += this.calculateDeduction(only_deduction, breakfastRate, lunchRate, dinnerRate, extraRate);
			}
			return amount;
		}
		
		public function calculateDeduction(deduction:TravelDeductionVO, breakfastRate:TravelRateRuleVO, lunchRate:TravelRateRuleVO, dinnerRate:TravelRateRuleVO, extraRate:TravelRateRuleVO):Number {
			var amount:Number = 0.0;
			var dailyAllowance:Number = this.getDailyAllowance(deduction.date);
			if (deduction.breakfast) {
				if (breakfastRate.cost != 0) {
					amount -= Number(breakfastRate.cost);
				} else if (breakfastRate.percent != 0) {
					amount -= Number(((dailyAllowance * breakfastRate.percent)/100).toFixed(2));
				}
			}
			if (deduction.lunch) {
				if (lunchRate.cost != 0) {
					amount -= Number(lunchRate.cost);
				} else if (lunchRate.percent != 0) {
					amount -= Number(((dailyAllowance * lunchRate.percent)/100).toFixed(2));
				}
			}
			if (deduction.dinner) {
				if (dinnerRate.cost != 0) {
					amount -= Number(dinnerRate.cost);
				} else if (dinnerRate.percent != 0) {
					amount -= Number(((dailyAllowance * dinnerRate.percent)/100).toFixed(2));
				}
			}
			if (deduction.breakfast && deduction.lunch && deduction.dinner) {
				amount += extraRate.cost;
			}
			
			// update deduction VO
			deduction.cost.cost = amount;
			deduction.cost.update();
			
			return amount;
		}
		
		
		// kalkuler diverse utlegg ==========================================================
		public function calculateOutlays():Number {
			var amount:Number = 0.0;
			var outlayList:ArrayCollection = ModelLocator.getInstance().travelOutlayList;
			for (var i:Number = 0; i < outlayList.length; i++) {
				amount += calculateOutlay(TravelOutlayVO(outlayList.getItemAt(i)));
			}
			return amount;
		}
		
		public function calculateOutlay(outlay:TravelOutlayVO):Number {
			outlay.cost.update();
			return Number(outlay.cost.local_cost);
		}
		
		
		// kalkuler reiseforskudd ===========================================================
		public function calculateTraveladvances():Number {
			var amount:Number = 0.0;
			var advanceList:ArrayCollection = ModelLocator.getInstance().travelAdvanceList;
			for (var i:Number = 0; i < advanceList.length; i++) {
				amount += calculateTraveladvance(TravelAdvanceVO(advanceList.getItemAt(i)));
			}
			return amount;
		}
		
		public function calculateTraveladvance(advance:TravelAdvanceVO):Number {
			return -(Number(advance.cost.toFixed(2)));
		}
		
		
		
		
		// collect correct rate =============================================================
		public function getRate(rateName:String):TravelRateRuleVO {
			var rateList:ArrayCollection = ModelLocator.getInstance().travelRateRulesList;
			for (var i:Number = 0; i < rateList.length; i++) {
				if (TravelRateRuleVO(rateList.getItemAt(i)).id == rateName) {
					return TravelRateRuleVO(rateList.getItemAt(i)); 
				}
			}
			return null;
		}
		
		public function getInternationalRate(countryCode:String, city:String=""):TravelRateInternationalVO {
			var rateList:ArrayCollection = ModelLocator.getInstance().travelRatesInternationalList;
			for (var i:Number = 0; i < rateList.length; i++) {
				if (TravelRateInternationalVO(rateList.getItemAt(i)).code == countryCode &&
					TravelRateInternationalVO(rateList.getItemAt(i)).city == city) {
					return TravelRateInternationalVO(rateList.getItemAt(i)); 
				}
			}
			return null;
		}

	}
}