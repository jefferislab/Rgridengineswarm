library(RMySQL)

#' Create a connection to the job control database
#'
#' @param group The group from default.file to use for the database connection
#' @param ... Other arguments to pass to the connection
#' @export
.jobcontrol_connection <- function(con=NULL, group="Rgridengineswarm", ...) {
	dbConnect(MySQL(), group=group, ...)
}


#' Create a chunk of work for a specified job
#' 
#' @param stufftodo The work that should be done by a worker working on this chunk
#' @param job_id The id of the job that this chunk should be part of
#' @param con The database connection to use to create the chunk
#' @param ... Other arguments to pass to the connection
#' @export
create_chunk <- function(stufftodo, job_id=1, con=NULL, ...) {
	if(is.null(con)){
		con <- .jobcontrol_connection(...)
		on.exit(dbDisconnect(con))
	}
	dbWriteTable(con, 'chunks', data.frame(job_id=job_id, stuff_to_do=stufftodo), append=TRUE, row.names=F)
}


#' Get a chunk of work to do from a specified job
#'
#' @param worker_id The id of the worker requesting a chunk
#' @param job_id The id of the job for which chunks are being requested
#' @param worker_name The name of the worker requesting a chunk. Default: 
#'   \code{<nodename>:<worker_id>}
#' @param nchunks The number of chunks requested
#' @param con The database connection to use for the chunk request
#' @param nullchunk The object to return if no chunks are returned
#' @return The database record corresponding to the chunk obtained
#' @param ... Other arguments to pass to the connection
#' @export
get_chunk <- function(worker_id, job_id=1,
                      worker_name=paste(Sys.info()['nodename'],worker_id,sep=":"),
                      nchunks=1, con=NULL, nullchunk=NA_character_, ...) {
	if(is.null(con)) {
		con <- .jobcontrol_connection(...)
		on.exit(dbDisconnect(con))
	}
	
	if(nchunks > 1) {
		l <- lapply(seq.int(nchunks), function(x)
			get_chunk(worker_id,job_id=job_id,con=con,nullchunk=nullchunk))
		
		return(do.call(rbind,l))
	}
	worker_id=as.integer(worker_id)
	if(is.na(worker_id)) stop("worker_id must be an integer")
	job_id=as.integer(job_id)
	if(is.na(job_id)) stop("job_id must be an integer")
	
	cmd <- sprintf("SELECT get_chunk(%d,%d,'%s')", worker_id, job_id, worker_name)
	res <- dbSendQuery(con, cmd)
	next_chunk_id <- fetch(res, n=-1)
	
	if(!length(next_chunk_id) || next_chunk_id[1,1] < 0) return(nullchunk)

	cmd <- sprintf("SELECT * FROM chunks WHERE id=%d ", next_chunk_id[1, 1])

	res <- dbSendQuery(con, cmd)
	chunkinfo <- fetch(res, n=-1)
	chunkinfo
}


#' Set a chunk as done
#'
#' @param worker_id The id of the worker that has completed the chunk
#' @param job_id The id of the job the chunk is part of
#' @param con The database connection to use for the update
#' @param chunk_id The id of the chunk
#' @return TRUE on success
#' @export
set_chunk_done <- function(worker_id=NULL, job_id=1, con=NULL, chunk_id=NULL) {
  worker_id=as.integer(worker_id)
  if(is.na(worker_id)) stop("worker_id must be an integer")
  job_id=as.integer(job_id)
  if(is.na(job_id)) stop("job_id must be an integer")
  chunk_id=as.integer(chunk_id)
  if(is.na(chunk_id)) stop("chunk_id must be an integer")
  cmd <- sprintf("SELECT set_chunk_done(%d, %d, %d)", worker_id, job_id, chunk_id);
	res <- dbSendQuery(con, cmd)
	updated_chunk_id <- fetch(res, n=-1)
	if(!length(updated_chunk_id) || updated_chunk_id[1, 1] < 0) return(FALSE)
	TRUE
}


#' Delete all the chunks associated with a specific job
#'
#' @param job_id The id of the job from which to delete all chunks
#' @param con The database connection to use for the deletion
#' @param ... Other arguments to pass to the connection
#' @return TRUE on success
#' @export
delete_job <- function(job_id, con=NULL, ...) {
	if(is.null(con)){
		con <- .jobcontrol_connection(...)
		on.exit(dbDisconnect(con))
	}
	if(length(job_id) > 1) return(sapply(job_id, delete_job, con))
	job_id=as.integer(job_id)
	if(is.na(job_id)) stop("job_id must be an integer")
	
	cmd <- sprintf("DELETE FROM chunks where job_id=%d", job_id)

	res <- try(dbSendQuery(con, cmd))
	!inherits(res, 'try-error')
}


#' Query Grid Engine to see if we can add more workers to the swarm
#'
#' @param cpusToLeave The number of CPUs in the pool to leave available for others
#' @param workerScript The filepath of the Rscript to call
#' @param availabilityDivisor The number with which to divide cpusToLeave to determine how many CPUs it is reasonable to assign to our task
#' @export
consider_adding_workers <- function(cpusToLeave, workerScript, availabilityDivisor=1) {
	message("==========")
	message("Consider adding more workers.")

	# Find total number of CPUs available via Grid Engine
	qstat <- paste(system("qstat -g c -ext", intern=T), collapse="")
	match <- regexpr("all.q\\s+[0-9]*.[0-9]*\\s*[0-9]*\\s*[0-9]*\\s*[0-9]*", qstat)
	cpusAvailLine <- substr(qstat, match, match+attr(match, "match.length")-1)
	match <- regexpr("all.q\\s+[0-9]*.[0-9]*\\s*[0-9]*\\s*[0-9]*\\s*", cpusAvailLine)
	cpusAvailable <- as.numeric(substr(cpusAvailLine, match+attr(match, "match.length"), nchar(cpusAvailLine)))

	# Make sure we don't use too many CPUs from the pool
	cpusAvailable <- floor(cpusAvailable / availabilityDivisor)
	
	message("  CPUs available (availability divisor [", availabilityDivisor, "] applied): ", cpusAvailable)
	message("  CPUs we should leave available: ", cpusToLeave)

	# Find the number of CPUs we are already using via Grid Engine
	username <- system("whoami", intern=T)
	quserstat <- system(paste0("qstat -u \"", username, "\""), intern=T)
	userCPUs <- 0
	for (i in 3:length(quserstat)) {
		match <- regexpr(paste0(username, "\\s*[a-z, A-Z]\\s*[0-9]*/[0-9]*/[0-9]*\\s*[0-9]*:[0-9]*:[0-9]*\\s*[^\\s]*\\s*[0-9]"), quserstat[i])
		userCPUsLine <- substr(quserstat[i], match, match+attr(match, "match.length")-1)
		match <- regexpr(paste0(username, "\\s*[a-z, A-Z]\\s*[0-9]*/[0-9]*/[0-9]*\\s*[0-9]*:[0-9]*:[0-9]*\\s*[^\\s]*\\s*"), userCPUsLine, perl=T)
		userCPUsSubLine <- substr(userCPUsLine, match+attr(match, "match.length"), nchar(userCPUsLine))
		match <- regexpr("[0-9]+", userCPUsSubLine)
		userCPUs <- userCPUs + as.numeric(substr(userCPUsSubLine, 1, match+attr(match, "match.length")))
	}
	message("  CPUs used by user: ", userCPUs)

	# Add more workers, if we can
	if (cpusAvailable > cpusToLeave) {
		add_workers(cpusAvailable, cpusToLeave, userCPUs, workerScript)
	} else {
		message("We should not add more workers.")
	}
	message("==========")
}


#' Use Grid Engine to add more workers
#'
#' @param cpusAvailable The number of CPUs available in the Grid Engine pool
#' @param cpusToLeave The number of CPUs in the pool to leave available for others
#' @param userCPUs The number of cpus
#' @param workerScript The filepath of the Rscript to call
add_workers <- function(cpusAvailable, cpusToLeave, userCPUs, workerScript) {
	message("We can add more workers.")
	message("  CPUs grabbable: ", cpusGrabbable <- cpusAvailable - cpusToLeave)
	message("  Num workers to add: ", numWorkersIncSize <- floor(cpusGrabbable / 2))
	message("  Grid Engine command: ", qsubCmd <- paste0("qsub -t ", userCPUs + 1, ":", userCPUs + numWorkersIncSize, " -b yes -cwd ", workerScript))
	message("  New total num workers: ", userCPUs + numWorkersIncSize)
	system(qsubCmd)
	message("==========")
}
