# How to RUN the distributed srsRAN scenario

1. Docker Swarm init
```bash
   docker swarm init
```
2. Start Network Core

```bash
cd srsran_split/srsRAN_Project-release_24_10/docker/
docker compose up 5gc --build
```

3. Start RIC

```bash
cd ./oran-sc-ric
docker compose up --build
```

4. Start CU

```bash
cd srsran_split/srsRAN_Project-release_24_10/docker/
docker stack deploy -c cu-ran-stack.yml oran_cu
```

5. Start DU
```bash
cd srsran_split/srsRAN_Project-release_24_10/docker/
docker stack deploy -c du-ran-stack.yml oran_du
```

### Configuration Files

Any changes must be made in the **cu-ran-stack.yml** and **du-ran-stack.yml** files, where the services to be executed in the Docker Swarm are configured.

The most critical aspect of both files is the IP and network configurations. If there are any changes to the network core, the IP must be updated in both files.

Another important point to note is that, although the IPs for these services are not assigned directly in these files, they are dynamically assigned during the application runtime. This is handled within the Dockerfile of both applications.