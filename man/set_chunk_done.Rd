\name{set_chunk_done}
\alias{set_chunk_done}
\title{Set a chunk as done}
\usage{
  set_chunk_done(worker_id = NULL, job_id = 1, con = NULL,
    chunk_id = NULL)
}
\arguments{
  \item{worker_id}{The id of the worker that has completed
  the chunk}

  \item{job_id}{The id of the job the chunk is part of}

  \item{con}{The database connection to use for the update}

  \item{chunk_id}{The id of the chunk}
}
\value{
  TRUE on success
}
\description{
  Set a chunk as done
}

