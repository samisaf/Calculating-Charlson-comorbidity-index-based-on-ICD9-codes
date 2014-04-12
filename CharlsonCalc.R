# See readme file. This script generates processes ICD9 codes, and produces a medical comrobidity table along with Charlson comorbidity index scores

# Importing pertinent libraries
library(reshape2)
library(plyr)
library(ggplot2)

# Setting input, and output paths
wd = getwd()
inputpath = paste(wd, "input", sep="/")
outputpath = paste(wd, "output", sep="/")

# Reading patients tables
## The first table contains the patients identifiers (MRN), date of birth(DOB), and date of hospitalization (DOH)
p1 = read.csv(file=paste(inputpath, "Patients1.csv", sep="/"), stringsAsFactors=FALSE)
p1$DOB = as.Date(p1$DOB) 
p1$DOH = as.Date(p1$DOH)
## The second table contains the patients' identifiers (MRN), the diagnosis codes (ICD9), and the dates of these diagnoses (DiagnosisDate)
p2 = read.csv(file=paste(inputpath, "Patients2.csv", sep="/"), stringsAsFactors=FALSE)
p2$DiagnosisDate = as.Date(p2$DiagnosisDate)

# Reading Charlson rules tables
## The first table describes the groups of comorbidities, and the scores attached to each group
c1 = read.csv(file=paste(inputpath, "CharlsonRules1.csv", sep="/"), stringsAsFactors=FALSE)
## The second table describes precedence rules for these groups
c2 = read.csv(file=paste(inputpath, "CharlsonRules2.csv", sep="/"), stringsAsFactors=FALSE)
## The third table associates each group with all of the partial ICD9 codes that can describe it
c3 = read.csv(file=paste(inputpath, "CharlsonRules3.csv", sep="/"), stringsAsFactors=FALSE)
## The fourth table describes the timeframe from the hospitalization date during which the codes are counted
c4 = read.csv(file=paste(inputpath, "CharlsonRules4.csv", sep="/"), stringsAsFactors=FALSE)

# Reading the ICD9 table
icd9 = read.csv(file=paste(inputpath, "ICD9Codes.csv", sep="/"), stringsAsFactors=FALSE)

# Processing
## Process patients tables, calculate age in years, and produce a combined Patients table
ageindays = as.numeric(p1$DOH -p1$DOB)
DAYSINYEAR = 365.242
Age = round(ageindays / DAYSINYEAR)
temp = p1
temp$Age = Age
Patients = join(x=temp, y=p2, by="MRN", type="full")

## Process Charlson tables
Comorbidities = join(x=c1, y=c2, by="Group", type="full")
Comorbidities = join(x=Comorbidities, y=c3, by="Group", type="full")
TIMEFRAME = c4$TimeFrameYears * DAYSINYEAR

## Linking partial, and complete ICD9 codes
## The icd9 table contains a list of all complete ICD9 codes and their corresponding descriptions. 
## The Patients table contains a complete `ICD9` column. However, the `Charlson` table contains partialICD9 column. 
## In order to be able to join the two tables, we have to link the partial, and complete codes. 
## A partial ICD9 corresponds a compelete ICD9 code if the complete code starts with the partial code. 
## A partial Code can correspond to many complete codes. 
## Read the partial ICD9 codes from the Comorbidities table, and add them to corresponding complete ICD9 codes from the icd9 table. 
ICD9 = data.frame(ICD9 = icd9$ICD9Code, stringsAsFactors=FALSE)
ICD9$PartialICD9 = NA
ICD9$LongName = icd9$LongName
ICD9$ShortName = icd9$ShortName
for (i in Comorbidities$PartialICD9){
  pattern = paste("^", i, sep="")
  match = grepl(pattern, ICD9$ICD9)
  if (any(match)) ICD9[match,]$PartialICD9 = i
}

## Create a Master table that combines all of the information required to produce the output
Master = join(x=Patients, y=ICD9, by="ICD9", type="left")
Master = join(x=Master, y=Comorbidities, by="PartialICD9", type="right")

## Applying the time frame rule
## Remove rows in which diangoses happened outside of the timeframe assigned
difference = abs(as.numeric(Master$DiagnosisDate - Master$DOH))
keep = difference<TIMEFRAME
keep[is.na(keep)] = TRUE
Master = Master[keep, ]

# Output
## Creating the patients comorbidities table
PatCom = data.frame(MRN = Master$MRN, Group = Master$Group)
PatCom = table(PatCom$MRN, PatCom$Group)
PatCom = as.data.frame.matrix(PatCom)
PatCom = PatCom > 0

## Calculate the score
score = PatCom
for (i in 1:nrow(c2)){
  g = c2$Group[i]
  s = c2$SupersededBy[i]
  score[, g] = score[, g] & ! score[, s]
}
score = t(score) * c1$Factor
score = t(score)
score = rowSums(score)

## Calculate added score from age
ages = data.frame(MRN = Master$MRN, Age = Master$Age)
ages = unique(ages)
ages$ScoreAge = floor((ages$Age - 40) / 10)
ages$ScoreAge[ages$ScoreAge<0] = 0

## Create the final table and calculate final score
Final = data.frame(MRN = row.names(PatCom), PatCom, Score = score)
Final = join(x=Final, y=ages, by="MRN", type="inner")
Final$Score = Final$Score + Final$ScoreAge

## Clean the table, and adjust the variable names
Final$Age = NULL
Final$ScoreAge = NULL
names(Final) = c("MRN", c1$Description, "Charlson Score")

## Create a melted table based on Final, exculding the Charlson Score
Display = melt(Final[-ncol(Final)], id.vars="MRN")
Display$variable = as.character(Display$variable)
Display = Display[order(Display$variable), ]
Display = Display[Display$value == TRUE, ]
table(Display$variable, Display$value)
plot = ggplot(Display) + aes(variable) + geom_histogram() + coord_flip() + xlab("Comorbidity") + ylab("Number of Patients")
plot

## Write output file
f = paste(outputpath, "Charlson.csv", sep="/")
g = paste(outputpath, "Graph.png", sep="/")
png(filename=g)
plot
dev.off() 
write.table(x=Final, file=f, sep=",", row.names=FALSE)