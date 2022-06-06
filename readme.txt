curl -s  https://raw.githubusercontent.com/cheluskin/mtrx/master/install.sh | bash -s test1.che.is

local   all             all                                     trust
# IPv4 local connections:
host    all             all             127.0.0.1/32            trust
# IPv6 local connections:
host    all             all             ::1/128                 trust

sudo -Hiu postgres bash -c "psql -c \"DROP database synapse;\""
sudo -Hiu postgres bash -c "psql -c \"DROP USER synapse_user;\""

pass 
/usr/bin/register_new_matrix_user -u root -p p@ssword -a -c config.yaml

