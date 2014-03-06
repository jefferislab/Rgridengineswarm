\name{get_chunk}
\alias{get_chunk}
\title{Get a chunk of work to do from a specified job}
\usage{
get_chunk(worker_id, worker_name = paste(Sys.info()["nodename"], worked_id,
  sep = ":"), nchunks = 1, job_id = 1, con = NULL,
  nullchunk = NA_character_, ...)
}
\arguments{
  \item{worker_id}{The id of the worker requesting a chunk}

  \item{worker_name}{The name of the worker requesting a
  chunk. Default: \code{<nodename>:<worker_id>}}

  \item{nchunks}{The number of chunks requested}

  \item{job_id}{The id of the job to request chunks of}

  \item{con}{The database connection to use for the chunk
  request}

  \item{nullchunk}{The object to return if no chunks are
  returned}

  \item{...}{Other arguments to pass to the connection}
}
\value{
The database record corresponding to the chunk obtained
}
\description{
Get a chunk of work to do from a specified job
}

