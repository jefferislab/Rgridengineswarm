\name{add_workers}
\alias{add_workers}
\title{Use Grid Engine to add more workers}
\usage{
add_workers(cpusAvailable, cpusToLeave, userCPUs, workerScript)
}
\arguments{
  \item{cpusAvailable}{The number of CPUs available in the
  Grid Engine pool}

  \item{cpusToLeave}{The number of CPUs in the pool to
  leave available for others}

  \item{userCPUs}{The number of cpus}

  \item{workerScript}{The filepath of the Rscript to call}
}
\description{
Use Grid Engine to add more workers
}

