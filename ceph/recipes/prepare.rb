require 'base64'

include_recipe "ceph"

class Chef::Recipe; include Ceph end

# this recipe should mount cluster and create directory for each app server (only if there are at least 2 osds active)
# !! this is tripsta specific recipe !!
if active_osds_count >= 2

  directory "/mnt/cluster"

  execute "mount /mnt/cluster" do
    command "ceph-fuse -m #{search(:node, 'recipes:ceph\:\:mon').first["ipaddress"]}:/ /mnt/cluster"
    not_if { IO.popen("mount").read.include?("/mnt/cluster") }
  end

  if IO.popen("mount").read.include?("/mnt/cluster")
    search(:node, 'recipes:application_server').each do |app|
      directory "/mnt/cluster/#{app[:hostname]}"
    end

    search(:node, 'recipes:mysql_backup').each do |backup|
      directory "/mnt/cluster/mysql_backup/#{backup[:hostname]}" do
        recursive true
      end
    end
  end

end
