#' Calibrate oli images to TM images
#'
#' Calibrate oli images to TM images using linear regression
#' @param oliwrs2dir character. oli WRS-2 scene directory path
#' @param tmwrs2dir character. TM WRS-2 scene directory path
#' @import raster
#' @import ggplot2
#' @import gridExtra
#' @export


olical_single = function(oli_file, tm_file, overwrite=F){
  
  get_intersection = function(files){
    int = intersect(extent(raster(files[1])),extent(raster(files[2])))
    if(length(files) >= 3){for(i in 3:length(files))int = intersect(extent(raster(files[i])), int)}
    return(int)
  }
  

#   sample_it = function(img, bins, n){
#     
#     mi = min(img, na.rm=T)
#     ma = max(img, na.rm=T)
#     
#     step = (ma - mi)/bins
#     breaks = seq(mi,ma,step)
#     
#     min_samp = array(n, bins)
#     for(i in 1:(length(breaks)-1)){
#       these = which(img > breaks[i] & img <= breaks[i+1])
#       if(i == 1){samp = sample(these, size=min(min_samp[i],length(these)))} else {
#         samp = c(samp, sample(these, size=min(min_samp[i],length(these))))
#       } 
#     }
#     return(samp)
#   }
  
  #define the filenames
  oli_sr_file = oli_file
  oli_mask_file = sub("l8sr.tif", "cloudmask.tif", oli_sr_file)
  ref_tc_file = tm_file
  ref_tca_file = sub("tc", "tca", ref_tc_file)
  ref_mask_file = sub("tc", "cloudmask", ref_tc_file)
  
  #make new directory
  dname = dirname(oli_sr_file)
  oliimgid = substr(basename(oli_sr_file),1,16)
  outdir = file.path(substr(dname,1,nchar(dname)-12),"calibration", oliimgid)  #-5
  dir.create(outdir, showWarnings = F, recursive=T)
  
  #check to see if single cal has already been run
  files = list.files(outdir)
  thesefiles = c("tca_cal_plot.png","tcb_cal_plot.png","tcg_cal_plot.png","tcw_cal_plot.png",
                 "tca_cal_samp.csv","tcb_cal_samp.csv","tcg_cal_samp.csv","tcw_cal_samp.csv")
  results = rep(NA,length(thesefiles))
  for(i in 1:length(results)){
    test = grep(thesefiles[i], files)
    results[i] = length(test) > 0
  }
  if(all(results) == T & overwrite == F){return(0)}
  
  
  #load files as raster
  oli_sr_img = brick(oli_sr_file)
  oli_mask_img = raster(oli_mask_file)
  ref_tc_img = brick(ref_tc_file)
  ref_tca_img  = raster(ref_tca_file)
  ref_mask_img = raster(ref_mask_file)
  
  #align the extents
  extent(oli_sr_img)  = alignExtent(oli_sr_img, ref_tc_img, snap="near")
  extent(oli_mask_img) = alignExtent(oli_mask_img, ref_tc_img, snap="near")
  extent(ref_tc_img)   = alignExtent(ref_tc_img, ref_tc_img, snap="near")
  extent(ref_tca_img)  = alignExtent(ref_tca_img, ref_tc_img, snap="near")
  extent(ref_mask_img) = alignExtent(ref_mask_img, ref_tc_img, snap="near")
  
  #crop the images to their intersection
  int = get_intersection(c(oli_mask_file,ref_mask_file))
  oli_b5_img = crop(subset(oli_sr_img,5),int)
  ref_tca_img = crop(ref_tca_img,int)
  oli_mask_img = crop(oli_mask_img,int)
  ref_mask_img = crop(ref_mask_img,int)
  
  #make a composite mask

  oli_mask_v = as.vector(oli_mask_img)
  ref_mask_v = as.vector(ref_mask_img)

  mask = oli_mask_v*ref_mask_v #make composite mask
  oli_mask_v = ref_mask_v = 0 # save memory
  
  #load oli and etm+ bands
  oli_b5_v = as.vector(oli_b5_img)
  ref_tca_v = as.vector(ref_tca_img)
  
  dif = oli_b5_v - ref_tca_v #find the difference
  oli_b5_v = ref_tca_v = 0 #save memory
  nas = which(mask == 0) #find the bads in the mask
  dif[nas] = NA #set the bads in the dif to NA so they are not included in the calc of mean and stdev
  stdv = sd(dif, na.rm=T) #get stdev of difference
  center = mean(dif, na.rm=T) #get the mean difference
  dif = dif < (center+stdv*2) & dif > (center-stdv*2) #find the pixels that are not that different
    
  
  goods = which(dif == 1)
  if(length(goods) < 20000){return(0)}
  
  #stratified sample
  #refpix = as.matrix(ref_tca_img)[goods]
  #samp = sample_it(refpix, bins=20, n=1000)
  
  #random sample
  samp = sample(1:length(goods), 20000)
  samp = goods[samp]
  sampxy = xyFromCell(oli_mask_img, samp)
  
  #save memory
  mask = 0
  
  #extract the sample pixels from the bands
  olisamp = extract(subset(oli_sr_img, 2:7), sampxy)
  tcsamp = extract(ref_tc_img, sampxy)
  
  #make sure the values are good for running regression on (diversity)
  unib2samp = length(unique(olisamp[,1]))
  unib3samp = length(unique(olisamp[,2]))
  unib4samp = length(unique(olisamp[,3]))
  unib5samp = length(unique(olisamp[,4]))
  unib6samp = length(unique(olisamp[,5]))
  unib7samp = length(unique(olisamp[,6]))
  
  unitcbsamp = length(unique(tcsamp[,1]))
  unitcgsamp = length(unique(tcsamp[,2]))
  unitcwsamp = length(unique(tcsamp[,3]))
  
  if(unib2samp < 15 | unib3samp < 15 | unib4samp < 15 | unib5samp < 15 | unib6samp < 15 | 
     unib7samp < 15 | unitcbsamp < 15 | unitcgsamp < 15 | unitcwsamp < 15){return()}
  
  
  olibname = basename(oli_sr_file)
  refbname = basename(ref_tc_file)
  
  tcb_tbl = data.frame(olibname,refbname,"tcb",sampxy,tcsamp[,1],olisamp)
  tcg_tbl = data.frame(olibname,refbname,"tcg",sampxy,tcsamp[,2],olisamp)
  tcw_tbl = data.frame(olibname,refbname,"tcw",sampxy,tcsamp[,3],olisamp)
  
  tcb_tbl = tcb_tbl[complete.cases(tcb_tbl),]
  tcg_tbl = tcg_tbl[complete.cases(tcg_tbl),]
  tcw_tbl = tcw_tbl[complete.cases(tcw_tbl),]
  
  ##############take this out################
  print(all.equal(nrow(tcb_tbl),nrow(tcg_tbl),nrow(tcw_tbl)))
  ###########################################
  
  cnames = c("oli_img","ref_img","index","x","y","refsamp","b2samp","b3samp","b4samp","b5samp","b6samp","b7samp") 
  colnames(tcb_tbl) = cnames
  colnames(tcg_tbl) = cnames
  colnames(tcw_tbl) = cnames
  
  #predict the indices
  #TCB
  outsampfile = file.path(outdir,paste(oliimgid,"_tcb_cal_samp.csv",sep=""))
  model = predict_oli_index(tcb_tbl, outsampfile)
  bcoef = model[[1]]
  bsamp = model[[2]]
  br = cor(bsamp$refsamp, bsamp$singlepred)
  
  #TCG
  outsampfile = file.path(outdir,paste(oliimgid,"_tcg_cal_samp.csv",sep=""))
  model = predict_oli_index(tcg_tbl, outsampfile)
  gcoef = model[[1]]
  gsamp = model[[2]]
  gr = cor(gsamp$refsamp, gsamp$singlepred)
  
  #TCW
  outsampfile = file.path(outdir,paste(oliimgid,"_tcw_cal_samp.csv",sep=""))
  model = predict_oli_index(tcw_tbl, outsampfile)
  wcoef = model[[1]]
  wsamp = model[[2]]
  wr = cor(wsamp$refsamp, wsamp$singlepred)
  
  #TCA
  singlepred = atan(gsamp$singlepred/bsamp$singlepred) * (180/pi) * 100
  refsamp = atan(gsamp$refsamp/bsamp$refsamp) * (180/pi) * 100
  tbl = data.frame(oli_img = olibname,
                   ref_img = refbname,
                   index = "tca",
                   x = tcb_tbl$x,
                   y = tcb_tbl$y,
                   refsamp,singlepred)
  final = tbl[complete.cases(tbl),]
  outsampfile = file.path(outdir,paste(oliimgid,"_tca_cal_samp.csv",sep=""))
  write.csv(final, outsampfile, row.names=F)
  
  #plot it
  r = cor(final$refsamp, final$singlepred)
  coef = rlm(final$refsamp ~ final$singlepred)

  pngout = sub("samp.csv", "plot.png",outsampfile)
  png(pngout,width=700, height=700)
  title = paste("tca linear regression: slope =",paste(signif(coef$coefficients[2], digits=3),",",sep=""),
                "y Intercept =",paste(round(coef$coefficients[1], digits=3),",",sep=""),
                "r =",signif(r, digits=3))
  plot(x=final$singlepred,y=final$refsamp,
       main=title,
       xlab=paste(olibname,"tca"),
       ylab=paste(refbname,"tca"))
  abline(coef = coef$coefficients, col="red")  
  dev.off()
  
  info = data.frame(oli_file = olibname, ref_file = refbname,
                    index = "tca", yint = as.numeric(coef$coefficients[1]),
                    b1c = as.numeric(coef$coefficients[2]), r=r)
  
  coefoutfile = file.path(outdir,paste(oliimgid,"_tca_cal_coef.csv",sep=""))
  write.csv(info, coefoutfile, row.names=F)
  
  
  #write out the coef files
  data.frame(oli_file=olibname, ref_file=refbname, index="tcb", bcoef, r=br)
  data.frame(oli_file=olibname, ref_file=refbname, index="tcg", gcoef, r=gr)
  data.frame(oli_file=olibname, ref_file=refbname, index="tcw", wcoef, r=wr)
  
  coefoutfile = file.path(outdir,paste(oliimgid,"_tcb_cal_coef.csv",sep=""))
  coefoutfile = file.path(outdir,paste(oliimgid,"_tcg_cal_coef.csv",sep=""))
  coefoutfile = file.path(outdir,paste(oliimgid,"_tcw_cal_coef.csv",sep=""))
  
  write.csv(info, coefoutfile, row.names=F)
  write.csv(info, coefoutfile, row.names=F)
  write.csv(info, coefoutfile, row.names=F)
  
  
  #outfile = file.path(outdir,paste(oliimgid,"_tc_cal_planes.png",sep=""))
  #make_tc_planes_comparison(bsamp, gsamp, wsamp, outfile)
  
}
