# Infrastructure for the deployment of Apache Kafka® UI via Docker to work with the Yandex Managed Service for Apache Kafka® clusters
#
# RU: https://cloud.yandex.ru/docs/managed-kafka/tutorials/deploy-kafka-ui
# EN: https://cloud.yandex.com/en/docs/managed-kafka/tutorials/deploy-kafka-ui
#
# Set the following settings:

locals {
  vm_username     = "" # Set the username to connect to the routing VM via SSH.
  vm_ssh_key_path = "" # Set the path to the SSH public key for the routing VM. Example: "~/.ssh/key.pub".
  kafka_username  = "" # Set the username of the Apache Kafka® user.
  kafka_password  = "" # Set the password of the Apache Kafka® user.
}

resource "yandex_vpc_network" "kafka-ui-network" {
  description = "Network for the Managed Service for Apache Kafka® cluster"
  name        = "kafka-ui-network"
}

resource "yandex_vpc_subnet" "subnet-a" {
  description    = "Subnet in the ru-central1-a availability zone"
  name           = "kafka-subnet-a"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.kafka-ui-network.id
  v4_cidr_blocks = ["10.1.0.0/24"]
}

resource "yandex_compute_instance" "vm-ubuntu-22-04" {
  description = "Virtual machine with Ubuntu 22.04"
  name        = "vm-ubuntu-22-04"
  platform_id = "standard-v1"
  zone        = "ru-central1-a"

  resources {
    cores  = 2
    memory = 2 # GB
  }

  boot_disk {
    initialize_params {
      image_id = "fd8vljd295nqdaoogf3g" # Image of the Ubuntu 22.04 operating system
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.subnet-a.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.kafka-ui-security-group.id]
  }

  metadata = {
    # Set a username and path for an SSH public key
    ssh-keys = "local.vm_username:${file(local.vm_ssh_key_path)}"
  }
}

resource "yandex_vpc_security_group" "kafka-ui-security-group" {
  name        = "kafka-ui-security-group-for-docker"
  description = "Security group for the Managed Service for Apache Kafka® cluster and for the VM"
  network_id  = yandex_vpc_network.kafka-ui-network.id

  ingress {
    description    = "Allows connections to the Managed Service for Apache Kafka® broker hosts from the internet"
    protocol       = "TCP"
    port           = 9091
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description    = "Allows connections to the Managed schema registry from the internet"
    protocol       = "TCP"
    port           = 443
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description    = "Allows SSH connections to the VM from the internet"
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description    = "Allows outgoing connections to any required resource"
    protocol       = "ANY"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_mdb_kafka_cluster" "kafka-ui-cluster" {
  description        = "Managed Service for Apache Kafka® cluster"
  environment        = "PRODUCTION"
  name               = "kafka-ui-cluster-for-docker"
  network_id         = yandex_vpc_network.kafka-ui-network.id
  security_group_ids = [yandex_vpc_security_group.kafka-ui-security-group.id]

  config {
    assign_public_ip = true
    brokers_count    = 1
    version          = "3.5"
    kafka {
      resources {
        disk_size          = 10 # GB
        disk_type_id       = "network-ssd"
        resource_preset_id = "s2.micro"
      }
    }

    zones = [
      "ru-central1-a"
    ]
  }
}

resource "yandex_mdb_kafka_user" "kafka-ui-user" {
  cluster_id = yandex_mdb_kafka_cluster.kafka-ui-cluster.id
  name       = local.kafka_username
  password   = local.kafka_password
}
