R Grid Engine worker swarm control
==================================

## Introduction
This simple package controls a swarm of workers, running on a [Grid Engine](http://gridscheduler.sourceforge.net) pool, using a MySQL database to store information about jobs. Functions are provided to add workers to a job after the initial workers have been set working.

Grid Engine has its own terminology with which we have tried to avoid collisions. We define a _job_ as a set of _chunks_ of work that are to be completed by a _swarm_ of _workers_. Each worker runs a copy of a script that requests chunks of work from the MySQL database and processes them. These workers may be distributed across multiple Grid Engine _tasks_, although workers added to the swarm at the same point will have the same Grid Engine task ID, each in a different _slot_. Workers may be placed on separate CPUs within the same _host_ or on different hosts as Grid Engine sees fit.

## Installation
Installation of the latest version from github can be achieved using Hadley Wickham's [devtools](https://github.com/hadley/devtools) package:
```r
install.packages("devtools")
library(devtools)
install_github("Rgridengineswarm", "jefferislab")
```

## Configuration
By default, the details of the database connection are read from the ``Rgridengineswarm`` group in the current user's ``.my.cnf`` (usually located at ```$HOME/.my.cnf```). Here is an example of what this might look like:

```
[Rgridengineswarm]
database = jobcontrol
user = fred
password = supersecure
host = 127.0.0.1
```

See the [mysql documentation](http://dev.mysql.com/doc/refman/5.1/en/option-files.html) for further details.

This default is read from a package option, `Rgridengineswarm.connpararams`,
which can be set to a different value like this.

```r
options(Rgridengineswarm.connpararams=list(group='myprojectjobcontrol'))
```
Although we recommend storing your connection parameters in a `.my.cnf` file, 
you can also set the default connection parameters directly like this:

```r
options(Rgridengineswarm.connpararams=list(database = 'jobcontrol', 
                                           user = 'fred', 
                                           password = 'supersecure', 
                                           host = '127.0.0.1'))
```
thereby avoiding use of `.my.cnf`.

### Setting up the MySQL database
#### Creating the table structure
The following SQL will create a table with the appropriate name and structure for the default configuration of the package. Note that the ``stuff_to_do`` field is merely a container for arbitrary data --- it is up to the worker script to determine how to handle the data returned.

```
DELIMITER $$

CREATE TABLE `chunks` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `status` int(11) NOT NULL COMMENT '0 available, 1 running, 2 done, -1 error',
  `worker_id` int(11) DEFAULT NULL,
  `worker_name` varchar(255) DEFAULT NULL,
  `stuff_to_do` varchar(255) DEFAULT NULL,
  `job_id` int(11) NOT NULL,
  `chunk_created` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `chunk_run` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `id_UNIQUE` (`id`),
  KEY `job_id_asc` (`job_id`)
) AUTO_INCREMENT=1 $$
```

#### Routines
Concurrent writes to the MySQL database are prevented by routines specified in the database definition. These are defined to prevent workers from trying to access the database while another worker is editing it. They are specified as follows:

##### get_chunk
```
DELIMITER $$

CREATE FUNCTION `get_chunk`(_worker_id INT, _job_id INT, _worker_name VARCHAR(255)) RETURNS int(11)
BEGIN
DECLARE chunk_id INT DEFAULT -1;
SET chunk_id=next_chunk(_job_id);
IF chunk_id>=0 THEN
	UPDATE chunks SET worker_id=_worker_id,status=1,chunk_run=CURRENT_TIMESTAMP,worker_name=_worker_name WHERE id=chunk_id;
END IF;
RETURN chunk_id;
END$$
```

##### next_chunk
```
DELIMITER $$

CREATE FUNCTION `next_chunk`(_job_id INT) RETURNS int(11)
BEGIN
DECLARE chunk_id INT DEFAULT -1;
SELECT id FROM chunks where status=0 AND job_id=_job_id ORDER BY id ASC LIMIT 1 INTO chunk_id;
RETURN chunk_id;
END$$
```

##### set_chunk_done
```
DELIMITER $$

CREATE FUNCTION `set_chunk_done`(_worker_id INT, _job_id INT, _chunk_id INT) RETURNS int(11)
BEGIN
DECLARE chunk_id INT DEFAULT -1;
UPDATE chunks SET status=2 WHERE id=_chunk_id AND worker_id=_worker_id AND job_id=_job_id;
SELECT id FROM chunks where status=2 AND id=_chunk_id AND job_id=_job_id AND worker_id=_worker_id ORDER BY id ASC LIMIT 1 INTO chunk_id;
RETURN chunk_id;
END$$
```


## Usage examples
### Creating jobs
As a simple example, this script creates a record of a job in the MySQL database, consisting of 50 chunks of work. The script below can then be run to start workers processing the job.
```r
#!/usr/bin/env Rscript
library(Rgridengineswarm)

# Set the job id
jobid <- 201

# Clear any old jobs with this id and create a new job of 50 chunks
delete_job(jobid)
create_chunk(1:50, job_id=jobid)
```

### A 'dumb' swarm of workers
This script queries the database to obtain the details of a chunk, marks the chunk as done and repeats until there are no chunks left to work on.
```r
#!/usr/bin/env Rscript
library(Rgridengineswarm)

# Set worker id
workerid <- as.numeric(Sys.getenv("SGE_TASK_ID"))

i <- 0
jccon=.jobcontrol_connection()
while(!all(is.na(chunk <- get_chunk(worker_id=workerid, job_id=jobid, con=jccon)))){
  message("Working on chunk ", chunk$stuff_to_do)
  i <- i + 1
  if(!set_chunk_done(worker_id=workerid, job_id=jobid, con=jccon, chunk_id=chunk$id)) message("Failed to set chunk ", chunk$id, " done.")
}
message("Finished ", i, " chunks!")
```
This swarm can be submitted to Grid Engine using ``qsub -t 1:<num_workers> -b yes -cwd example_prime_worker.R``, where ``<num_workers>`` should be set to the number of workers you wish to work on the job. Since gridengine spews out a bunch of log files in the working directory it normally makes sense to make a special folder to hold them. I normally do something like this:

```sh
cd path/to/my/project
mkdir sgelogs
cd sgelogs
qsub -t 1:<num_workers> -b yes -cwd path/to/example_prime_worker.R
```

Once running, more workers can be added to the swarm by running a new ``qsub`` command, but the swarm will not manage its size automatically. For a swarm you can set running and leave to manage itself, see the next example.


### A self-updating swarm of workers
In this more advanced example, a swarm of workers is initialised and periodically checks the number of CPUs available in the Grid Engine pool to see if the size of the swarm can be increased. To do this, a 'prime worker' is assigned the task of setting up the job records in the MySQL database as well as submitting new requests to Grid Engine to alter the swarm size.
```r
#!/usr/bin/env Rscript
library(Rgridengineswarm)
library(digest)

# Job data
jobid <- 401
workerid <- as.numeric(Sys.getenv("SGE_TASK_ID"))
workername <- paste0(system("hostname", intern=T), ":", workerid)
numChunks <- 100
cpusToLeave <- 70
workerScript <- "example_prime_worker.R"

# Open connection to database
jccon <- .jobcontrol_connection()

# Log which id the worker claims to have
message("I am worker ", workerid, " (", workername, ").")

# Check if this worker should set up chunks, or wait for them to be set up
if(workerid == 1) {
	# This worker is the prime worker, so set up the chunks in the job
	message("Setting up ", numChunks, " chunks for job ", jobid, "...")
	
	# Delete any old listings for the same job id and create chunks
	delete_job(jobid, con=jccon)
	create_chunk(unlist(lapply(1:numChunks, digest)), job_id=jobid, con=jccon)

	# Try and add some more workers now that the job is stored in the MySQL database
	consider_adding_workers(cpusToLeave, workerScript, availabilityDivisor=3)
}

# Work on chunks
chunksCompleted <- 0
while(!all(is.na(chunk <- get_chunk(worker_id=workerid, worker_name=workername, job_id=jobid, con=jccon)))) {
	message("Working on chunk ", chunk$id, " (belongs to job ", jobid, "), doing ", chunk$stuff_to_do, "...")
	
	# Our chunks don't correspond to any actual work, so we sleep for some some time to simulate the act of doing work
	Sys.sleep(floor(runif(1, 50, 100)))
	chunksCompleted <- chunksCompleted + 1
	if(!set_chunk_done(worker_id=workerid, job_id=jobid, con=jccon, chunk_id=chunk$id)) message("Failed to set chunk ", chunk$id, " done.")

	# Check to see if we can spawn more workers
	if (workerid == 1) {
		if (chunksCompleted %% 5 == 0) {
			consider_adding_workers(cpusToLeave, workerScript, availabilityDivisor=3)
		}
	}
}
message("Finished ", chunksCompleted, " chunks!")
```
Assuming this Rscript is saved as ``example_prime_worker.R``, the swarm can be initialised with ``qsub -t 1:1 -b yes -cwd example_prime_worker.R``. This will create an initial worker that will dutifully set up the details of the job in the MySQL database. After this, it will try and add more workers to the job and start work on a chunk itself. After it has completed a few chunks, it will again check to see if more workers can be added to the job. This process repeats until there are no more chunks to start working on. It is possible for chunk to be started, but not completed, in which case the status will be set to 1 (0 and 2 indicate unstarted and completed jobs, respectively) --- in this situation the MySQL database should be inspected and the status of the incomplete jobs set to 0 or 2, as appropriate, with the swarm being started again if necessary.
