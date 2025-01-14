#### Drought germination models ####

#load(Germination_clean_data.R)

#Load libraries
library(rjags)
library(R2jags)
library(ggmcmc)
library(broom.mixed)
library(car) # use car package for logit function- adjusts to avoid infinity


# load data 
source("R/Germination/cleaning_germination_lab_data.R")

# inverse logit function
invlogit<-function(x){a <- exp(x)/(1+exp(x))
a[is.nan(a)]=1
return(a)
}

# function to standardize dpe var
standard <- function(x) (x - mean(x, na.rm=T)) / ((sd(x, na.rm=T)))

#Jags hates NA in independent variables
#Take out NAs in the data that you don't want to model

##############################
# Ver.alp
# take out the too many zer0s
Ver_alp_germination_traits <- Ver_alp_germination_traits %>% 
  mutate(water_potential = as.numeric(water_potential))
guddat <-  Ver_alp_germination_traits %>% filter (siteID == "GUD") %>% filter(water_potential < 8)
lavdat <- Ver_alp_germination_traits %>% filter (siteID == "LAV") %>% filter(water_potential < 9)
skjdat <- Ver_alp_germination_traits %>% filter (siteID == "SKJ") %>% filter(water_potential < 8)
ulvdat <- Ver_alp_germination_traits %>% filter (siteID == "ULV") 

dat <- bind_rows(guddat, lavdat, skjdat, ulvdat)
# group level effects
 site <- factor(dat$siteID)
 petridish <- factor(dat$petri_dish)

# independent variables
WP <- as.numeric(standard(as.numeric(dat$water_potential)))
WP_MPa <- as.numeric(standard(dat$WP_MPa))
Precip <- as.numeric(standard(dat$precip))

# dependent variables
GermN <- as.numeric(dat$n_germinated)
NumSeedDish <- as.numeric(dat$seeds_in_dish)  #Viability test information needs to be inculded here
N <- as.numeric(length(GermN))

treatmat <- model.matrix(~Precip*WP_MPa)
n_parm <- as.numeric(ncol(treatmat))

# look at the data before the analysis
ggplot(dat, aes(x=water_potential,y = logit(n_germinated/seeds_in_dish, adjust = 0.01)))+
  geom_point()+facet_wrap(~siteID)

jags.data <- list("treatmat", "GermN", "N", "NumSeedDish", "site", "n_parm")
jags.param <- c("b",  "Presi", "rss", "rss_new", "sig1") 

model_GermN <- function(){
  #group effects
  #for (j in 1:4){lokaliteter[j]~dnorm(0, prec1)}
  #likelihood
  for (i in 1:N){
    GermN[i] ~ dbinom(mu[i], NumSeedDish[i])
    
    # linear predictor
      logit(mu[i]) <- inprod(b, treatmat[i,]) #+ lokaliteter[site[i]]

     # residual sum of squares
     res[i] <- pow((GermN[i]/NumSeedDish[i]) - (mu[i]), 2)
     GermN_new[i] ~ dbinom(mu[i], NumSeedDish[i])
     res_new[i] <- pow((GermN_new[i]/NumSeedDish[i]) - (mu[i]), 2)
   }
   
    for(i in 1:n_parm){b[i] ~ dnorm(0,1.0E-6)} #dnorm in JAGS uses mean and precision (0 = mean and 1.0E-6 = precision) different from dnorm in R that has variance and not precision.
    #prec1 ~ dgamma(0.001, 0.001) 
    #sig1 <- 1/sqrt(prec1) #getting variance of the random effect
  
  # #derived params
   rss <- sum(res[])
   rss_new <- sum(res_new[])
}

results_GermN <- jags.parallel(data = jags.data,
                               #inits = inits.fn,
                               parameters.to.save = jags.param,
                               n.iter = 200000,
                               model.file = model_GermN,
                               n.thin = 5,
                               n.chains = 3,
                               n.burnin = 35000)
results_GermN

# traceplots
s <- ggs(as.mcmc(results_GermN))
ggs_traceplot(s, family="b") 

# check Gelman Rubin Statistics
gelman.diag(as.mcmc(results_GermN))

# Posterior predictive check
plot(results_GermN$BUGSoutput$sims.list$rss_new, results_GermN$BUGSoutput$sims.list$rss,
     main = "",)
abline(0,1, lwd = 2, col = "black")

mean(results_GermN$BUGSoutput$sims.list$rss_new > results_GermN$BUGSoutput$sims.list$rss)

## put together for figure  and r^2
mcmc <- results_GermN$BUGSoutput$sims.matrix
coefs = mcmc[, c("b[1]", "b[2]", "b[3]", "b[4]")]
fit = coefs %*% t(treatmat)
resid = sweep(fit, 2, logit(GermN/NumSeedDish, adjust = 0.01), "-")
var_f = apply(fit, 1, var)
var_e = apply(resid, 1, var)
R2 = var_f/(var_f + var_e)
tidyMCMC(as.mcmc(R2), conf.int = TRUE, conf.method = "HPDinterval")

#residuals
coefs2 = apply(coefs, 2, median)
fit2 = as.vector(coefs2 %*% t(treatmat))
resid2 <- (GermN/NumSeedDish) - invlogit(fit2)
sresid2 <- resid2/sd(resid2)
ggplot() + geom_point(data = NULL, aes(y = resid2, x = invlogit(fit2)))
hist(resid2)

# check predicted versus observed
yRep = sapply(1:nrow(mcmc), function(i) rbinom(nrow(dat), NumSeedDish[i], fit[i,]))
ggplot() + geom_density(data = NULL, aes(x = (as.vector(yRep)/NumSeedDish),
                               fill = "Model"), alpha = 0.5) + 
  geom_density(data = dat, aes(x = (GermN/NumSeedDish), fill = "Obs"), alpha = 0.5)

# generate plots
newdat <- expand.grid(WP_MPa = seq(min(WP_MPa), max(WP_MPa), length = 50),
                      Precip = c(unique(standard(dat$precip))))

xmat <- model.matrix(~Precip*WP_MPa, newdat)
fit = coefs %*% t(xmat)
newdat <- newdat %>% cbind(tidyMCMC(fit, conf.int = TRUE))

graphdat <- dat %>% mutate(estimate = (n_germinated/seeds_in_dish)) %>%
  rename(site = siteID)
graphdat$WP_MPa <- standard(graphdat$WP_MPa)                   
graphdat$Precip <- as.numeric(standard(dat$precip))

ggplot()+ 
  geom_point(data=graphdat, aes(x=WP_MPa, y=estimate, colour = factor(Precip)),alpha=.15)+
  geom_ribbon(data=newdat, aes(ymin=invlogit(conf.low), ymax=invlogit(conf.high), x=WP_MPa, 
                               fill = factor(Precip)), alpha=0.35)+
  geom_line(data=newdat, aes(y = invlogit(estimate), x = WP_MPa, colour = factor(Precip)))+
  #facet_wrap(~Precip)+
  #scale_colour_manual("Treatment", values=c("gray", "red")) + 
  #scale_fill_manual("Treatment", values=c("dark gray", "red")) + 
  scale_x_continuous("Standardized WP") + 
  scale_y_continuous("Germination %")+ 
  # theme(axis.text.y = element_text(size=7,colour= "black"),
  #       axis.text.x= element_text(size=7, colour="black"), 
  #       axis.title=element_text(size=7),strip.text=element_text(size=5),
  #       plot.title=element_text(size=7),
  #       legend.title=element_text(size=5), legend.text=element_text(size=4),
  #       legend.margin=margin(0,0,0,0),legend.position = c(0.2,0.3),
  #       legend.box.margin=margin(-10,-2,-10,-5),legend.justification="left",
  #       legend.key.size = unit(0.15, "cm"))+ #labs(title="Colonization probability")+
  theme(panel.background = element_rect(fill='white', colour='black'))+
  theme(panel.grid.major=element_blank(), panel.grid.minor=element_blank())


#########################################################################################
# Sib.pro

# take out the too many zer0s
Sib_pro_germination_traits <- Sib_pro_germination_traits %>% 
  mutate(water_potential = as.numeric(water_potential))
guddat <- Sib_pro_germination_traits %>% filter (siteID == "GUD") %>% filter(water_potential < 6)
lavdat <- Sib_pro_germination_traits %>% filter (siteID == "LAV") %>% filter(water_potential < 10)
skjdat <- Sib_pro_germination_traits %>% filter (siteID == "SKJ") %>% filter(water_potential < 9)
ulvdat <- Sib_pro_germination_traits %>% filter (siteID == "ULV") %>% filter(water_potential < 10)

dat <- bind_rows(guddat, lavdat, skjdat, ulvdat)
dat <- dat %>% filter(!is.na(n_germinated))
# group level effects
site <- factor(dat$siteID)
petridish <- factor(dat$petri_dish)

# independent variables
WP <- as.numeric(standard(as.numeric(dat$water_potential)))
WP_MPa <- as.numeric(standard(dat$WP_MPa))
Precip <- as.numeric(standard(dat$precip))

# dependent variables
GermN <- as.numeric(dat$n_germinated)
NumSeedDish <- as.numeric(dat$seeds_in_dish)  #Viability test information needs to be inculded here
N <- as.numeric(length(GermN))

treatmat <- model.matrix(~Precip*WP_MPa)
n_parm <- as.numeric(ncol(treatmat))

# look at the data before the analysis
ggplot(dat, aes(x=water_potential,y = logit(n_germinated/seeds_in_dish,
                                                                   adjust = 0.01)))+
  geom_point()+facet_wrap(~siteID)

jags.data <- list("treatmat", "GermN", "N", "NumSeedDish", "site", "n_parm")
jags.param <- c("b",  "Presi", "rss", "rss_new", "sig1") 

#Run the model 
results_GermN <- jags.parallel(data = jags.data,
                               #inits = inits.fn,
                               parameters.to.save = jags.param,
                               n.iter = 200000,
                               model.file = model_GermN,
                               n.thin = 5,
                               n.chains = 3,
                               n.burnin = 35000)
results_GermN

# traceplots
s <- ggs(as.mcmc(results_GermN))
ggs_traceplot(s, family="b") 

# check Gelman Rubin Statistics
gelman.diag(as.mcmc(results_GermN))

# Posterior predictive check
plot(results_GermN$BUGSoutput$sims.list$rss_new, results_GermN$BUGSoutput$sims.list$rss,
     main = "",)
abline(0,1, lwd = 2, col = "black")

mean(results_GermN$BUGSoutput$sims.list$rss_new > results_GermN$BUGSoutput$sims.list$rss)

## put together for figure  and r^2
mcmc <- results_GermN$BUGSoutput$sims.matrix 
coefs = mcmc[, c("b[1]", "b[2]", "b[3]", "b[4]")]
fit = coefs %*% t(treatmat)
resid = sweep(fit, 2, logit(GermN/NumSeedDish, adjust = 0.01), "-")
var_f = apply(fit, 1, var)
var_e = apply(resid, 1, var)
R2 = var_f/(var_f + var_e)
tidyMCMC(as.mcmc(R2), conf.int = TRUE, conf.method = "HPDinterval")

#residuals
coefs2 = apply(coefs, 2, median)
fit2 = as.vector(coefs2 %*% t(treatmat))
resid2 <- (GermN/NumSeedDish) - invlogit(fit2)
sresid2 <- resid2/sd(resid2)
ggplot() + geom_point(data = NULL, aes(y = resid2, x = invlogit(fit2)))
hist(resid2)

# check predicted versus observed
yRep = sapply(1:nrow(mcmc), function(i) rbinom(nrow(dat), NumSeedDish, fit[i,]))
ggplot() + geom_density(data = NULL, aes(x = (as.vector(yRep)/NumSeedDish),
                                         fill = "Model"), alpha = 0.5) + 
  geom_density(data = dat, aes(x = (GermN/NumSeedDish), fill = "Obs"), alpha = 0.5)

# generate plots
newdat <- expand.grid(WP_MPa = seq(min(WP_MPa), max(WP_MPa), length = 50),
                      Precip = c(unique(standard(dat$precip))))

xmat <- model.matrix(~Precip*WP_MPa, newdat)
fit = coefs %*% t(xmat)
newdat <- newdat %>% cbind(tidyMCMC(fit, conf.int = TRUE))

graphdat <- dat %>% mutate(estimate = (n_germinated/seeds_in_dish)) %>%
  rename(site = siteID)
graphdat$WP_MPa <- standard(graphdat$WP_MPa)                   
graphdat$Precip <- as.numeric(standard(dat$precip))

ggplot()+ 
  geom_point(data=graphdat, aes(x=WP_MPa, y=estimate, colour = factor(Precip)),alpha=.15)+
  geom_ribbon(data=newdat, aes(ymin=invlogit(conf.low), ymax=invlogit(conf.high), x=WP_MPa, 
                               fill = factor(Precip)), alpha=0.35)+
  geom_line(data=newdat, aes(y = invlogit(estimate), x = WP_MPa, colour = factor(Precip)))+
  #facet_wrap(~Precip)+
  #scale_colour_manual("Treatment", values=c("gray", "red")) + 
  #scale_fill_manual("Treatment", values=c("dark gray", "red")) + 
  scale_x_continuous("Standardized WP") + 
  scale_y_continuous("Germination %")+ 
  # theme(axis.text.y = element_text(size=7,colour= "black"),
  #       axis.text.x= element_text(size=7, colour="black"), 
  #       axis.title=element_text(size=7),strip.text=element_text(size=5),
  #       plot.title=element_text(size=7),
  #       legend.title=element_text(size=5), legend.text=element_text(size=4),
  #       legend.margin=margin(0,0,0,0),legend.position = c(0.2,0.3),
  #       legend.box.margin=margin(-10,-2,-10,-5),legend.justification="left",
  #       legend.key.size = unit(0.15, "cm"))+ #labs(title="Colonization probability")+
  theme(panel.background = element_rect(fill='white', colour='black'))+
  theme(panel.grid.major=element_blank(), panel.grid.minor=element_blank())

#############################################
# Ver.alp - 
# take out the too many zer0s
Ver_alp_germination_traits <- Ver_alp_germination_traits %>% 
  mutate(water_potential = as.numeric(water_potential))
guddat <-  Ver_alp_germination_traits %>% filter (siteID == "GUD") %>% filter(water_potential < 8)
lavdat <- Ver_alp_germination_traits %>% filter (siteID == "LAV") %>% filter(water_potential < 9)
skjdat <- Ver_alp_germination_traits %>% filter (siteID == "SKJ") %>% filter(water_potential < 8)
ulvdat <- Ver_alp_germination_traits %>% filter (siteID == "ULV") 

dat <- bind_rows(guddat, lavdat, skjdat, ulvdat)
dat <- dat %>% filter(!is.na(days_to_max_germination)) %>% filter(water_potential<8) # weird values throwing off entire models
# group level effects
site <- factor(dat$siteID)
petridish <- factor(dat$petri_dish)

# independent variables
WP <- as.numeric(standard(as.numeric(dat$water_potential)))
WP_MPa <- as.numeric(standard(dat$WP_MPa))
Precip <- as.numeric(standard(dat$precip))

# dependent variables
DtoM <- as.numeric(dat$days_to_max_germination)
N <- as.numeric(length(DtoM))

treatmat <- model.matrix(~Precip*WP_MPa)
n_parm <- as.numeric(ncol(treatmat))

# look at the data before the analysis
ggplot(dat, aes(x=water_potential, y = days_to_max_germination), adjust = 0.01)+
  geom_point()+facet_wrap(~siteID)

jags.data <- list("treatmat", "DtoM", "N",  "site", "n_parm")
jags.param <- c("b", "rss", "rss_new", "r") 

model_DtoM<- function(){
  #group effects
  for (j in 1:4){lokaliteter[j]~dnorm(0, prec1)}
  #likelihood
  for (i in 1:N){
    DtoM[i] ~ dnegbin(p[i], r)
    # linear predictor
    log(mu[i]) <- inprod(b, treatmat[i,]) + lokaliteter[site[i]]
    p[i] <- r/(r+mu[i])
    
    # residual sum of squares
    res[i] <- pow(DtoM[i] - mu[i], 2)
    DtoM_new[i] ~ dnegbin(p[i], r)
    res_new[i] <- pow(DtoM_new[i] - mu[i], 2)
  }
  
  for(i in 1:n_parm){b[i] ~ dnorm(0,1.0E-6)} #dnorm in JAGS uses mean and precision (0 = mean and 1.0E-6 = precision) different from dnorm in R that has variance and not precision.
  prec1 ~ dgamma(0.001, 0.001) 
  sig1 <- 1/sqrt(prec1) #getting variance of the random effect
  r~ dunif(0,50)
  # #derived params
  rss <- sum(res[])
  rss_new <- sum(res_new[])
}

results_DtoM <- jags.parallel(data = jags.data,
                               #inits = inits.fn,
                               parameters.to.save = jags.param,
                               n.iter = 50000,
                               model.file = model_DtoM,
                               n.thin = 5,
                               n.chains = 3)
results_DtoM

# traceplots
s <- ggs(as.mcmc(results_DtoM))
ggs_traceplot(s, family="b") 

# check Gelman Rubin Statistics
gelman.diag(as.mcmc(results_DtoM))

# Posterior predictive check
plot(results_DtoM$BUGSoutput$sims.list$rss_new, results_DtoM$BUGSoutput$sims.list$rss,
     main = "",)
abline(0,1, lwd = 2, col = "black")

mean(results_DtoM$BUGSoutput$sims.list$rss_new > results_DtoM$BUGSoutput$sims.list$rss)

## put together for figure  and r^2
mcmc <- results_DtoM$BUGSoutput$sims.matrix
coefs = mcmc[, c("b[1]", "b[2]", "b[3]", "b[4]")]
fit = coefs %*% t(treatmat)
resid = sweep(fit, 2, log(DtoM), "-")
var_f = apply(fit, 1, var)
var_e = apply(resid, 1, var)
R2 = var_f/(var_f + var_e)
tidyMCMC(as.mcmc(R2), conf.int = TRUE, conf.method = "HPDinterval")

#residuals
coefs2 = apply(coefs, 2, median)
fit2 = as.vector(coefs2 %*% t(treatmat))
resid2 <- (DtoM) - exp(fit2)
sresid2 <- resid2/sd(resid2)
ggplot() + geom_point(data = NULL, aes(y = resid2, x = invlogit(fit2)))
hist(resid2)

# check predicted versus observed
yRep = sapply(1:nrow(mcmc), function(i) rpois(nrow(dat), exp(fit[i,])))
ggplot() + geom_density(data = NULL, aes(x = (as.vector(yRep)),
                                         fill = "Model"), alpha = 0.5) + 
  geom_density(data = dat, aes(x = (DtoM), fill = "Obs"), alpha = 0.5)

# generate plots
newdat <- expand.grid(WP_MPa = seq(min(WP_MPa), max(WP_MPa), length = 50),
                      Precip = c(unique(standard(dat$precip))))

xmat <- model.matrix(~Precip*WP_MPa, newdat)
fit = coefs %*% t(xmat)
newdat <- newdat %>% cbind(tidyMCMC(fit, conf.int = TRUE))

graphdat <- dat %>% mutate(estimate = days_to_max_germination) %>%
  rename(site = siteID)
graphdat$WP_MPa <- standard(graphdat$WP_MPa)                   
graphdat$Precip <- as.numeric(standard(dat$precip))

ggplot()+ 
  geom_point(data=graphdat, aes(x=WP_MPa, y=estimate, colour = factor(Precip)),alpha=.15)+
  geom_ribbon(data=newdat, aes(ymin=exp(conf.low), ymax=exp(conf.high), x=WP_MPa, 
                               fill = factor(Precip)), alpha=0.35)+
  geom_line(data=newdat, aes(y = exp(estimate), x = WP_MPa, colour = factor(Precip)))+
  #facet_wrap(~Precip)+
  #scale_colour_manual("Treatment", values=c("gray", "red")) + 
  #scale_fill_manual("Treatment", values=c("dark gray", "red")) + 
  scale_x_continuous("Standardized WP") + 
  scale_y_continuous("Germination %")+ 
  # theme(axis.text.y = element_text(size=7,colour= "black"),
  #       axis.text.x= element_text(size=7, colour="black"), 
  #       axis.title=element_text(size=7),strip.text=element_text(size=5),
  #       plot.title=element_text(size=7),
  #       legend.title=element_text(size=5), legend.text=element_text(size=4),
  #       legend.margin=margin(0,0,0,0),legend.position = c(0.2,0.3),
  #       legend.box.margin=margin(-10,-2,-10,-5),legend.justification="left",
  #       legend.key.size = unit(0.15, "cm"))+ #labs(title="Colonization probability")+
  theme(panel.background = element_rect(fill='white', colour='black'))+
  theme(panel.grid.major=element_blank(), panel.grid.minor=element_blank())


#############################################
# Sib.pro - days to germination
# take out the too many zer0s
Sib_pro_germination_traits <- Sib_pro_germination_traits %>% 
  mutate(water_potential = as.numeric(water_potential))
guddat <- Sib_pro_germination_traits %>% filter (siteID == "GUD") %>% filter(water_potential < 6)
lavdat <- Sib_pro_germination_traits %>% filter (siteID == "LAV") %>% filter(water_potential < 9)
skjdat <- Sib_pro_germination_traits %>% filter (siteID == "SKJ") %>% filter(water_potential < 8)
ulvdat <- Sib_pro_germination_traits %>% filter (siteID == "ULV") %>% filter(water_potential < 9)

dat <- bind_rows(guddat, lavdat, skjdat, ulvdat)
dat <- dat %>% filter(!is.na(days_to_max_germination)) 
# group level effects
site <- factor(dat$siteID)
petridish <- factor(dat$petri_dish)

# independent variables
WP <- as.numeric(standard(as.numeric(dat$water_potential)))
WP_MPa <- as.numeric(standard(dat$WP_MPa))
Precip <- as.numeric(standard(dat$precip))

# dependent variables
DtoM <- as.numeric(dat$days_to_max_germination)
N <- as.numeric(length(DtoM))

treatmat <- model.matrix(~Precip*WP_MPa)
n_parm <- as.numeric(ncol(treatmat))

# look at the data before the analysis
ggplot(dat, aes(x=water_potential, y = days_to_max_germination), adjust = 0.01)+
  geom_point()+facet_wrap(~siteID)

jags.data <- list("treatmat", "DtoM", "N",  "site", "n_parm")
jags.param <- c("b", "rss", "rss_new", "r", "sig1") 

results_DtoM <- jags.parallel(data = jags.data,
                              #inits = inits.fn,
                              parameters.to.save = jags.param,
                              n.iter = 50000,
                              model.file = model_DtoM,
                              n.thin = 5,
                              n.chains = 3)
results_DtoM

# traceplots
s <- ggs(as.mcmc(results_DtoM))
ggs_traceplot(s, family="b") 

# check Gelman Rubin Statistics
gelman.diag(as.mcmc(results_DtoM))

# Posterior predictive check
plot(results_DtoM$BUGSoutput$sims.list$rss_new, results_DtoM$BUGSoutput$sims.list$rss,
     main = "",)
abline(0,1, lwd = 2, col = "black") # these are still not great but not sure what to do 

mean(results_DtoM$BUGSoutput$sims.list$rss_new > results_DtoM$BUGSoutput$sims.list$rss)

## put together for figure  and r^2
mcmc <- results_DtoM$BUGSoutput$sims.matrix
coefs = mcmc[, c("b[1]", "b[2]", "b[3]", "b[4]")]
fit = coefs %*% t(treatmat)
resid = sweep(fit, 2, log(DtoM), "-")
var_f = apply(fit, 1, var)
var_e = apply(resid, 1, var)
R2 = var_f/(var_f + var_e)
tidyMCMC(as.mcmc(R2), conf.int = TRUE, conf.method = "HPDinterval")

#residuals
coefs2 = apply(coefs, 2, median)
fit2 = as.vector(coefs2 %*% t(treatmat))
resid2 <- (DtoM) - exp(fit2)
sresid2 <- resid2/sd(resid2)
ggplot() + geom_point(data = NULL, aes(y = resid2, x = invlogit(fit2)))
hist(resid2)

# check predicted versus observed
yRep = sapply(1:nrow(mcmc), function(i) rpois(nrow(dat), exp(fit[i,])))
ggplot() + geom_density(data = NULL, aes(x = (as.vector(yRep)),
                                         fill = "Model"), alpha = 0.5) + 
  geom_density(data = dat, aes(x = (DtoM), fill = "Obs"), alpha = 0.5)

# generate plots
newdat <- expand.grid(WP_MPa = seq(min(WP_MPa), max(WP_MPa), length = 50),
                      Precip = c(unique(standard(dat$precip))))

xmat <- model.matrix(~Precip*WP_MPa, newdat)
fit = coefs %*% t(xmat)
newdat <- newdat %>% cbind(tidyMCMC(fit, conf.int = TRUE))

graphdat <- dat %>% mutate(estimate = days_to_max_germination) %>%
  rename(site = siteID)
graphdat$WP_MPa <- standard(graphdat$WP_MPa)                   
graphdat$Precip <- as.numeric(standard(dat$precip))

ggplot()+ 
  geom_point(data=graphdat, aes(x=WP_MPa, y=estimate, colour = factor(Precip)))+
  geom_ribbon(data=newdat, aes(ymin=exp(conf.low), ymax=exp(conf.high), x=WP_MPa, 
                               fill = factor(Precip)), alpha=0.35)+
  geom_line(data=newdat, aes(y = exp(estimate), x = WP_MPa, colour = factor(Precip)))+
  #facet_wrap(~Precip)+
  #scale_colour_manual("Treatment", values=c("gray", "red")) + 
  #scale_fill_manual("Treatment", values=c("dark gray", "red")) + 
  scale_x_continuous("Standardized WP") + 
  scale_y_continuous("Germination %")+ 
  # theme(axis.text.y = element_text(size=7,colour= "black"),
  #       axis.text.x= element_text(size=7, colour="black"), 
  #       axis.title=element_text(size=7),strip.text=element_text(size=5),
  #       plot.title=element_text(size=7),
  #       legend.title=element_text(size=5), legend.text=element_text(size=4),
  #       legend.margin=margin(0,0,0,0),legend.position = c(0.2,0.3),
  #       legend.box.margin=margin(-10,-2,-10,-5),legend.justification="left",
  #       legend.key.size = unit(0.15, "cm"))+ #labs(title="Colonization probability")+
  theme(panel.background = element_rect(fill='white', colour='black'))+
  theme(panel.grid.major=element_blank(), panel.grid.minor=element_blank())

#########################################################################################
# germination on a seedling basis

