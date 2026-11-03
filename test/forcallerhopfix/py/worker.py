class Worker:
    def handle_job(self, job):
        return job


def dispatch_jobs(pool, jobs):
    for job in jobs:
        pool.handle_job(job)
