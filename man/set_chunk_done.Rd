\name{set_chunk_done}
\alias{set_chunk_done}
\title{Set a chunk as done}
\usage{
set_chunk_done(worker_id = NULL, job_id = 1, con = NULL,
  chunk_id = NULL, ...)
}
\arguments{
  \item{worker_id}{The id of the worker that has completed
  the chunk}

  \item{chunk_id}{The id of the chunk}

  \item{job_id}{The id of the job for which chunks are
  being requested}

  \item{con}{The database connection to use for the chunk
  request or \code{NULL} to indicate that the function
  should make and close a connection just for this
  request.}

  \item{...}{Other arguments for creating the connection
  when \code{NULL}}
}
\value{
TRUE on success
}
\description{
Set a chunk as done
}

