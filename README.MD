# PostgreSQL Backup and S3 Upload Using Ansible

This guide outlines the steps to set up PostgreSQL on a slave server, back up its data, and upload the backup to an AWS S3 bucket using Ansible.

---

## Prerequisites
1. **Two Ubuntu Servers**:
   - One as the Ansible control node.
   - One as the managed (slave) node.
2. **AWS IAM User**:
   - Create an IAM user with programmatic access.
   - Generate and save the Access Key ID and Secret Access Key.
3. **S3 Bucket**:
   - Create an S3 bucket to store backups.

---

## Steps

### Step 1: Install Ansible on the Control Node
1. Add the Ansible PPA:
   ```bash
   sudo apt-add-repository ppa:ansible/ansible
   sudo apt update
   ```
2. Install Ansible:
   ```bash
   sudo apt install ansible -y
   ```

---

### Step 2: Configure SSH Between Control and Slave Nodes
1. Generate an SSH key on the control node:
   ```bash
   ssh-keygen -t rsa -b 4096
   ```
2. Copy the public key to the slave server:
   ```bash
   cat /home/ubuntu/.ssh/id_rsa.pub
   ```
   Paste the key into the slave server's `~/.ssh/authorized_keys` file.

---

### Step 3: Set Up the Inventory File
1. Open the default inventory file:
   ```bash
   sudo nano /etc/ansible/hosts
   ```
2. Add the following configuration:
   ```ini
   [servers]
   pgtest ansible_host=<slave-server-ip>

   [all:vars]
   ansible_python_interpreter=/usr/bin/python3
   ```

---

### Step 3: Testing Connection
After setting up the inventory file to include your servers, it’s time to check if Ansible is able to connect to these servers and run commands via SSH.

For this guide, we’ll be using the Ubuntu root account because that’s typically the only account available by default on newly created servers. If your Ansible hosts already have a regular sudo user created, you are encouraged to use that account instead.

You can use the -u argument to specify the remote system user. When not provided, Ansible will try to connect as your current system user on the control node.

From your local machine or Ansible control node, run:

```bash
ansible all -m ping -u ubuntu
```

---

### Step 4: Test Connectivity
Test the connection to the slave server:
```bash
ansible all -m ping -u ubuntu
```

---

### Step 5: Install PostgreSQL on the Slave Node
1. Install PostgreSQL:
   ```bash
   sudo apt install postgresql postgresql-contrib -y
   ```
2. Configure PostgreSQL:
   ```bash
   sudo -u postgres psql
   ALTER USER postgres WITH PASSWORD 'password';
   CREATE DATABASE my_database;
   \c my_database
   ```
3. Create a `users` table and populate it with sample data:
   ```sql
   CREATE TABLE users (
       id SERIAL PRIMARY KEY,
       name VARCHAR(100),
       email VARCHAR(100)
   );

   INSERT INTO users (name, email) VALUES
   ('Alice Johnson', 'alice.johnson@example.com'),
   ('Bob Smith', 'bob.smith@example.com');
   ```

---

### Step 6: Configure PostgreSQL Authentication
1. Edit the PostgreSQL authentication file:
   ```bash
   sudo nano /etc/postgresql/14/main/pg_hba.conf
   ```
   Update the line for `postgres` to use `md5` instead of `peer`.
2. Restart PostgreSQL:
   ```bash
   sudo systemctl restart postgresql
   ```

---

### Step 7: Configure AWS and Ansible Variables
1. Create an Ansible variable file (`vars.yml`):
   ```yaml
   postgres_user: postgres
   postgres_db: my_database
   postgres_password: password
   s3_bucket: your_s3_bucket_name
   s3_prefix: backups
   aws_access_key: YOUR_AWS_ACCESS_KEY
   aws_secret_key: YOUR_AWS_SECRET_KEY
   aws_region: YOUR_AWS_REGION
   ```
2. Encrypt the variable file:
   ```bash
   ansible-vault encrypt vars.yml
   ```

---

### Step 8: Create the Ansible Playbook
Create a playbook `pg_backup.yml` to automate the backup and upload process:

```yaml
---
- name: PostgreSQL Backup and S3 Upload
  hosts: servers
  remote_user: ubuntu
  become: yes

  vars_files:
    - vars.yml

  tasks:
    - name: Update all packages
      apt:
        name: "*"
        state: latest
        update_cache: yes

    - name: Install required packages
      apt:
        name:
          - python3-pip
          - python3-boto3
          - python3-botocore
          - postgresql-client
        state: present

       - name: Install unzip
      apt: 
        name: unzip
        state: latest

    - name: Install AWS CLI
      shell: |
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip awscliv2.zip
        ./aws/install
      args:
        creates: /usr/local/bin/aws

    - name: Configure AWS CLI
      shell: |
        aws configure set aws_access_key_id {{ aws_access_key }}
        aws configure set aws_secret_access_key {{ aws_secret_key }}
        aws configure set region {{ aws_region }}
      no_log: true

    - name: Create backup directory
      file:
        path: "/var/backups/postgresql"
        state: directory
        mode: "0700"

    - name: Perform PostgreSQL backup
      shell: |
        PGPASSWORD={{ postgres_password }} pg_dump -U {{ postgres_user }} -d {{ postgres_db }} > /var/backups/postgresql/{{ postgres_db }}-{{ ansible_date_time.date }}-{{ ansible_date_time.time }}.sql
      args:
        executable: "/bin/bash"

    - name: Compress the backup
      shell:
        cmd: gzip -f /var/backups/postgresql/{{ postgres_db }}-{{ ansible_date_time.date }}-{{ ansible_date_time.time }}.sql
        executable: "/bin/bash"

    - name: Upload backup to S3
      aws_s3:
        bucket: "{{ s3_bucket }}"
        object: "{{ s3_prefix }}/{{ postgres_db }}-{{ ansible_date_time.date }}-{{ ansible_date_time.time }}.sql.gz"
        src: "/var/backups/postgresql/{{ postgres_db }}-{{ ansible_date_time.date }}-{{ ansible_date_time.time }}.sql.gz"
        mode: put
        permission: "private"
```

---

### Step 9: Execute the Playbook
Run the playbook:
```bash
ansible-playbook pg_backup.yml --ask-vault-pass
```

---

### Step 10: Verify the Backup
1. Check the backup in the S3 bucket.
2. Test restoration using the uploaded file if required.

