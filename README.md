auto-consul
===========

Ruby gem for bootstrapping consul cluster members

# Example usage

Given two vagrant boxes, each with consul and auto-consul installed.

Export your AWS keys into the environment in each:

    ```
    export AWS_ACCESS_KEY_ID=...
    export AWS_SECRET_ACCESS_KEY=...
    ```

This will allow the AWS SDK to pick them up.

The server, screen A:

    auto-consul -r s3://my-bucket/consul/test-cluster \
                -a 192.168.50.100 \
                -n server1 \
                run

Then, server screen B:

    while true; do
        auto-consul -r s3://my-bucket/consul/test-cluster \
                    -a 192.168.50.100 \
                    -n server1 \
                    heartbeat
        sleep 60
    done

The first launches the agent, the latter checks its run status and
issues a heartbeat to the specified S3 bucket.

Because this is the first server, there will be no heartbeats in the
bucket (assuming a fresh bucket/key combination).  Therefore, the agent
will be launched in server mode, along with the bootstrap option to
initialize the raft cluster for state management.

Look in the S3 bucket above, under "servers", and you should see
a timestamped entry like "20140516092731-server1".  This is produced
by the "heartbeat" command and allows new agents to discover active
members of the cluster for joining.

Having seen the server heartbeat, go to the agent vagrant box, and
do something similar.  Screen A:

    auto-consul -r s3://my-bucket/consul/test-cluster \
                -a 192.168.50.101 \
                -n agent1 \
                run

In this case, the agent will discover the server via its heartbeat.  It
will know that we have enough servers (it defaults to only wanting one;
that's fine for dev/testing but not good for availability) and thus
simply join as a normal agent.

Screen B:

    while true; do
        auto-consul -r s3://my-bucket/consul/test-cluster \
                    -a 192.168.50.101 \
                    -n agent1 \
                    heartbeat
        sleep 60
    done

This generates heartbeats like the server did, but while the server
sends heartbeats both to "servers" and "agents" in the bucket, the
normal agent sends heartbeats only to "agents".

# Mode determination

Given a desired number of servers (defaulting to 1) and a registry
(for now, an S3-style URL), the basic algorithm is:

- Are there enough servers?
  - Yes: Be an agent.  Done.
  - No: are there no servers?
    - Yes: Be a server with bootstrap mode.  Done.
    - No: Be a server without bootstrap mode, joining with others.  Done.

There is very obviously a race condition in the determination of node
mode.  In practice, it should be easy enough to coordinate things such
that the race doesn't cause problems.  Longer term, we'll need to revise
the mode determination logic to use a backend supporting optimistic
locking or some such.  (A compare-and-swap pattern would work fine; consul
itself would allow for this given one existing server).

## Heartbeats and membership

The heartbeats give us a rough indication of cluster membership.  The
tool uses an expiry time (in seconds) to determine which heartbeats are
still active, and will purge any expired heartbeats from the registry
whenever it encounters them.

Each heartbeat tells us:
- The node's name within the consul cluster
- The timestamp of the heartbeat (the freshness)
- The IP at which the node can be reached for cluster join operations.

For now, it is necessary to run the heartbeat utility in parallel to the
run utility.  In subsequent work we may want to have these things coordinated
by one daemon, but given the experimental nature of this project it's not
worth caring about just yet.

The heartbeat asks consul for its status and from that determines if it
is running as a server or regular agent (or if it is running at all).  If
consul is not running at all, no heartbeat will be emitted.

The default expiry is 120 seconds.  It is recommended that heartbeats fire
at half that duration (60 seconds).

# Cluster join

After the node mode is determined, it's necessary (except in the case of
a bootstrap-mode server) to join a cluster by contacting an extant member.

This is the primary purpose of the heartbeat registry; a server-mode node
will find the IP (from the active heartbeats) of a *server*, and use that
IP to join the cluster.  An agent-mode node will find the IP of an *agent*
for the join operation.

In a production-ready tool, we would have a monitor on the registry and
keep trying new hosts until a join succeeds.  But in this experimental
phase, it just picks the first member in the relevant list and uses that.
If that member is actually down, then the join simply won't work.

