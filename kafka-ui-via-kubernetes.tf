# Infrastructure for the deployment of Apache Kafka® UI via the Yandex Managed Service for Kubernetes to work with the Yandex Managed Service for Apache Kafka® clusters
#
# RU: https://cloud.yandex.ru/docs/managed-kafka/tutorials/deploy-kafka-ui
# EN: https://cloud.yandex.com/en/docs/managed-kafka/tutorials/deploy-kafka-ui
#
# Set the following settings:

locals {
  kafka_username  = "" # Set the username of the Apache Kafka® user.
  kafka_password  = "" # Set the password of the Apache Kafka® user.
  folder_id       = "" # Your cloud folder ID, same as for the Yandex Cloud provider.
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

resource "yandex_vpc_security_group" "kafka-ui-security-group" {
  name        = "kafka-ui-security-group-for-kubernetes"
  description = "Security group for the Managed Service for Apache Kafka® cluster, the Managed Service for Kubernetes cluster and the Kubernetes node group"
  network_id  = yandex_vpc_network.kafka-ui-network.id

  ingress {
    description       = "Allows connections to the Managed Service for Apache Kafka® broker hosts from the internet"
    protocol          = "TCP"
    port              = 9091
    v4_cidr_blocks    = ["0.0.0.0/0"]
  }

  ingress {
    description       = "Allows connections to the Managed schema registry from the internet"
    protocol          = "TCP"
    port              = 443
    v4_cidr_blocks    = ["0.0.0.0/0"]
  }

  ingress {
    description       = "Allows availability checks from the load balancer's range of addresses. Required for the operation of a fault-tolerant cluster and load balancer services"
    protocol          = "TCP"
    predefined_target = "loadbalancer_healthchecks"
    from_port         = 0
    to_port           = 65535
  }

  ingress {
    description       = "Allows the master-node and node-node interaction within the security group"
    protocol          = "ANY"
    predefined_target = "self_security_group"
    from_port         = 0
    to_port           = 65535
  }

  ingress {
    description       = "Allows the pod-pod and service-service interaction"
    protocol          = "ANY"
    from_port         = 0
    to_port           = 65535
    v4_cidr_blocks    = concat(yandex_vpc_subnet.subnet-a.v4_cidr_blocks)
  }

  ingress {
    description       = "Allows receipt of the debugging ICMP packets from internal subnets"
    protocol          = "ICMP"
    v4_cidr_blocks    = concat(yandex_vpc_subnet.subnet-a.v4_cidr_blocks)
  }

  ingress {
    description       = "Allows incoming traffic from the internet to the NodePort port range. Add ports or change existing ones to the required ports"
    protocol          = "TCP"
    from_port         = 30000
    to_port           = 32767
    v4_cidr_blocks    = ["0.0.0.0/0"]
  }

  egress {
    description       = "Allows all outgoing traffic. Nodes can connect to Yandex Container Registry, Object Storage, Docker Hub to name but a few"
    protocol          = "ANY"
    from_port         = 0
    to_port           = 65535
    v4_cidr_blocks    = ["0.0.0.0/0"]
  }
}

resource "yandex_mdb_kafka_cluster" "kafka-ui-cluster" {
  description        = "Managed Service for Apache Kafka® cluster"
  environment        = "PRODUCTION"
  name               = "kafka-ui-cluster-for-kubernetes"
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

resource "yandex_kubernetes_cluster" "k8s-cluster" {
  name = "k8s-cluster"
  network_id = yandex_vpc_network.kafka-ui-network.id
  master {
    master_location {
      zone      = yandex_vpc_subnet.subnet-a.zone
      subnet_id = yandex_vpc_subnet.subnet-a.id
    }
    security_group_ids = [yandex_vpc_security_group.kafka-ui-security-group.id]
  }
  service_account_id      = yandex_iam_service_account.myaccount.id
  node_service_account_id = yandex_iam_service_account.myaccount.id
  depends_on = [
    yandex_resourcemanager_folder_iam_member.k8s-clusters-agent,
    yandex_resourcemanager_folder_iam_member.vpc-public-admin,
    yandex_resourcemanager_folder_iam_member.images-puller
  ]
}

resource "yandex_iam_service_account" "myaccount" {
  name        = "k8s-account"
  description = "Kubernetes service account"
}

resource "yandex_resourcemanager_folder_iam_member" "k8s-clusters-agent" {
  # The service account is assigned the k8s.clusters.agent role
  folder_id = local.folder_id
  role      = "k8s.clusters.agent"
  member    = "serviceAccount:${yandex_iam_service_account.myaccount.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "vpc-public-admin" {
  # The service account is assigned the vpc.publicAdmin role
  folder_id = local.folder_id
  role      = "vpc.publicAdmin"
  member    = "serviceAccount:${yandex_iam_service_account.myaccount.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "images-puller" {
  # The service account is assigned the container-registry.images.puller role
  folder_id = local.folder_id
  role      = "container-registry.images.puller"
  member    = "serviceAccount:${yandex_iam_service_account.myaccount.id}"
}

resource "yandex_kubernetes_node_group" "k8s-node-group" {
  description = "Node group for the Managed Service for Kubernetes cluster"
  name        = "k8s-node-group"
  cluster_id  = yandex_kubernetes_cluster.k8s-cluster.id

  scale_policy {
    fixed_scale {
      size = 1 # Number of hosts
    }
  }

  allocation_policy {
    location {
      zone = "ru-central1-a"
    }
  }

  instance_template {
    platform_id = "standard-v2"

    network_interface {
      nat                = true
      subnet_ids         = [yandex_vpc_subnet.subnet-a.id]
      security_group_ids = [yandex_vpc_security_group.kafka-ui-security-group.id]
    }

    resources {
      memory = 4 # RAM quantity in GB
      cores  = 4 # Number of CPU cores
    }

    boot_disk {
      type = "network-hdd"
      size = 64 # Disk size in GB
    }
  }
}
