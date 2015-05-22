.onLoad <- function(libname, pkgname) {
  # set default connection parameters
  connparams=getOption('Rgridengineswarm.connpararams')
  if(is.null(connparams))
    options(Rgridengineswarm.connpararams=list(group='Rgridengineswarm'))
}
