#############################################
# DATASET 1: 50k unfiltered sites from baboon RRBS dataset
# GOAL: look at properties of raw data, practice filtering data
#############################################

# raw data files
mcounts=read.delim('unfilt_mcounts_50k.txt',header=F)
counts=read.delim('unfilt_counts_50k.txt',header=F)
dim(mcounts); dim(counts)
tail(mcounts); tail(counts)

# how does coverage vary across sites?
hist((apply(counts,1,mean)),col='steelblue', xlab='Mean read depth',xlim=c(0,200),breaks=200,main='')

# what does the methylation level distribution look like?
ratio<-mcounts/counts
plot(density(apply(ratio,1,function(x) mean(x,na.rm=TRUE))),col='steelblue', main='',xlab='Mean methylation level',lwd=3)

# filter out low variance sites, sites with low mean coverage, and sites with lots of missing data
mean_cov<-apply(counts,1,function(x) mean(x,na.rm=TRUE))
missing<-apply(counts,1,function(x) length(which(is.na(x))))
mean_meth<-apply(ratio,1,function(x) mean(x,na.rm=TRUE))

counts_filt<-counts[which(mean_cov>5 & mean_meth>0.1 & mean_meth<0.9 & missing<(69*0.75)),]
mcounts_filt<-mcounts[which(mean_cov>5 & mean_meth>0.1 & mean_meth<0.9 & missing<(69*0.75)),]
ratio2<-mcounts_filt/counts_filt

# compare the filtered and non filtered data
plot(density(apply(ratio,1,function(x) mean(x,na.rm=TRUE))),col='steelblue', xlab='Mean methylation level',lwd=3,main='')
lines(density(apply(ratio2,1,function(x) mean(x,na.rm=TRUE))),col='red',lwd=3)
legend('topright',c('unfiltered','filtered'),col=c('steelblue','red'),lwd=c(3,3))

plot(density(apply(counts,1,function(x) mean(x,na.rm=TRUE))),col='steelblue', xlab='Mean read depth',xlim=c(0,50),lwd=3,main='')
lines(density(apply(counts_filt,1,function(x) mean(x,na.rm=TRUE))),col='red',lwd=3)
legend('topright',c('unfiltered','filtered'),col=c('steelblue','red'),lwd=c(3,3))

#############################################
# DATASET 2: 1 chromosome (~38k) of filtered sites from baboon RRBS dataset
# GOAL: PCA, understand batch effects and major sources of variance in the data, look at MACAU output
#############################################

# raw data files
counts=read.delim('filtered_counts_chr10_n61.txt',header=F)
mcounts=read.delim('filtered_mcounts_chr10_n61.txt',header=F)
info=read.delim('sample_info_n61.txt')
dim(counts); dim(mcounts); dim(info)

# let's look at the major sources of variance and check for any batch effects
# impute missing data to run PCA
require(impute)
ratio<-mcounts[,2:dim(mcounts)[2]]/counts[,2:dim(mcounts)[2]]
imputed<-impute.knn(as.matrix(ratio),rowmax = 0.75)
ratio2<-as.data.frame(imputed$data)

pca <- prcomp(t(ratio2)) 
summary(pca)

# check for potential batch/technical effects
# conversion rate
hist(info$Conversion_rate,breaks=20,col='steelblue', main='',xlab='Bisulfite conversion rate')
# this looks like a binary variable, so let's create one
info$Conversion_rate2<-0
info$Conversion_rate2[info$Conversion_rate<0.99]<-1

pvals<-apply(pca$x[,1:10],2,function(x) summary(lm(x~info$Conversion_rate2))$coefficients[2,4])
plot(c(1:10),-log10(pvals),xlab="PC",ylab="-log10 p-val: conversion rate effect",ylim=c(0,2))
abline(h=-log10(0.05),lty=2,xlim=c(0,2))
boxplot(pca$x[,1] ~ as.factor(info$Conversion_rate2),xlab='conversion rate batch',ylab='PC1 loading')

# could be a problem if batch effects are confounded with our variable of interest; let's check
fisher.test(table(info$Diet,info$Conversion_rate2))

# ok, ready for some analyses!
# it will take too long for you to run MACAU on this dataset, but let's look at the output
# p-values are from an analysis of diet effects controlling for age, batch/conversion rate, and 
output<-read.delim('macau_output_chr10_n61.txt')

# qqplot against uniform (empirical null is uniform)
par(mfrow=c(1,1))
unif<-runif(dim(output)[1])
qqplot(-log10(unif),-log10(output$pvalue),pch=20,col='steelblue',xlim=c(0,7),ylim=c(0,7),ylab='-log10 pval: diet effect',xlab='-log10 pval: null distribution')
x=c(0,1);y=c(0,1); abline(lm(y~x),lty=2)

# FDR correction
require(qvalue)
output$qval<-qvalue(output$pvalue)$qvalues
# how many sites are significant at a 10% FDR?
length(which(output$qval<0.1))

#############################################
# DATASET 3: simulated data with coverage properties of baboon RRBS dataset
# GOAL: simulate a small bisulfite sequencing dataset, run a beta binomial model and a linear model, compare the output
#############################################

# simulate 1000 sites, 20% of them are true positives
sites<-c(1:1000)
betas<-c(rep(0,length(sites)*0.8),rep(1,length(sites)*0.2)) 
xvar<-as.numeric(info$Diet)
n<-length(xvar)
mcounts_sim <- matrix(nrow=max(sites),ncol=n)
counts_sim <- matrix(nrow=max(sites),ncol=n)
	
for (i in sites) {
	theta_j <- xvar*betas[i] + rnorm(n, 0, 1)
	theta_j2 <- 1/(1 + exp(theta_j))
	# use coverage properties of baboon RRBS data
	coverage_n_j <- counts[sample(c(1:dim(counts)[1]),1),2:(n+1)]
				
	for (k in c(1:n)) {
			tot_counts <- as.numeric(coverage_n_j[k])
				if (tot_counts < 1){mcounts_sim[i,k] <- 0
				counts_sim[i,k] <- 0} else {mcounts_sim[i,k] <- rbinom(1, as.numeric(coverage_n_j[k]), theta_j2[k])
				counts_sim[i,k] <- tot_counts} } }

# look at the simulated data
tail(mcounts_sim); tail(counts_sim)

# compare coverage properties of real and simulated data
plot(density(apply(counts[1:10000,2:(n+1)],1,function(x) mean(x,na.rm=TRUE))),col='steelblue', main='', xlab='Mean read depth',xlim=c(0,50),lwd=3)
lines(density(apply(counts_sim,1,function(x) mean(x,na.rm=TRUE))),col='red',lwd=3)
legend('topright',c('real','simulated'),col=c('steelblue','red'),lwd=c(3,3))

# run a few different models 
ratio_sim<-mcounts_sim/counts_sim
# t-test
pval1<-apply(ratio_sim,1,function(x) t.test(x~as.factor(info$Diet))$p.value)

# linear model
ratio_norm<-t(apply(ratio_sim,1,function(a){return(qqnorm(a,plot=F)$x)}))
pval2<-apply(ratio_norm,1,function(x) summary(lm(x~as.factor(info$Diet)))$coefficients[2,4])

# beta binomial (run later on your own; it's slow)
# source('beta_binomial_function.R')
# param=c(-1,0.5,0)
# c=xvar
# pval3<-c()
# for (p in sites) {
# x=as.vector(mcounts_sim[p,])
# y=as.vector(counts_sim[p,])
# pval3<-c(pval3, bbfit(x,y,c)) }

# read in beta binomial example output for this set of simulations
pval3=read.delim('beta_binomial_pvals.txt')
	
unif<-runif(1000)
qqplot(-log10(unif),-log10(pval1),pch=20,col='steelblue',xlim=c(0,7),ylim=c(0,7),xlab='-log10 pval: null distribution',ylab='-log10 pval: observed p-values')
x=c(0,1);y=c(0,1)
abline(lm(y~x),lty=2)
temp<-qqplot(-log10(unif),-log10(pval2),plot.it=FALSE)
points(temp$x,temp$y,pch=20,col='red')
temp<-qqplot(-log10(unif),-log10(pval3$bb_pvals),plot.it=FALSE)
points(temp$x,temp$y,pch=20,col='gray55')
legend('bottomright',c('t-test','linear model','beta binomial'),col=c('steelblue','red','gray55'),pch=c(20,20,20))

# how many true positives are detected by each method?
length(which(qvalue(pval1)$qvalues[801:1000]<0.1))
length(which(qvalue(pval2)$qvalues[801:1000]<0.1))
length(which(qvalue(pval3$bb_pvals)$qvalues[801:1000]<0.1))

fdrval<-seq(0.01,0.2,by=0.01)
numgenes<-matrix(nrow=3,ncol=length(fdrval),NA)
for(i in 1:length(fdrval)){
  fdrthres<-fdrval[i]
  numgenes[1,i]<-sum(qvalue(pval1)$qvalues[801:1000]<fdrthres)
  numgenes[2,i]<-sum(qvalue(pval2)$qvalues[801:1000]<fdrthres)
  numgenes[3,i]<-sum(qvalue(pval3$bb_pvals)$qvalues[801:1000]<fdrthres)
}

par(mfrow=c(1,1))
plot(numgenes[1,]~fdrval,type='l',xlab='fdr threshold',ylab='significant sites',lwd=5,frame.plot=F,cex.lab=1.5,cex.axis=1.5,col='steelblue4',ylim=c(0,150),xlim=c(0,.2))
lines(numgenes[2,]~fdrval,type='l',lwd=5,col='purple4')
lines(numgenes[3,]~fdrval,type='l',col='goldenrod',lwd=5)
legend("bottomright",c('t-test','linear model','beta binomial model'),fill=c('steelblue4','purple4','goldenrod'),bty='n',cex=1.5)