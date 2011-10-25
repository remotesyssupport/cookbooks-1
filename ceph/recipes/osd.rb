require 'base64'

ruby_block "set osd id" do
  block do
    node.set[:ceph][:osd_id] = search(:node, 'recipes:ceph\:\:osd').size
  end
  not_if { node[:ceph][:osd_id] } 
end

include_recipe "ceph"
directory "#{node[:ceph][:mount_point]}/ceph-stage2"

if node[:ceph][:osd_id]
  directory "#{node[:ceph][:mount_point]}/osd.#{node[:ceph][:osd_id]}"
end

if search(:node, 'recipes:ceph\:\:osd').all? { |osd| osd[:ceph][:osd_id] }
  ["#{node[:ceph][:mount_point]}/ceph-stage2/conf", "/etc/ceph/ceph.conf"].each do |conf|
    template conf do
      source "ceph.conf.erb"
      variables(
        :mon => search(:node, 'recipes:ceph\:\:mon'),
        :mds => search(:node, 'recipes:ceph\:\:mds'),
        :osd => search(:node, 'recipes:ceph\:\:osd'),
        :initial_mds => search(:node, 'ceph:initial_mds')
      )
    end
  end
end

template "#{node[:ceph][:mount_point]}/ceph-stage2/caps" do
  source "caps.erb"
end

service "ceph-osd" do
  service_name "ceph-osd"
  start_command "/etc/init.d/ceph start osd"
  stop_command "/etc/init.d/ceph stop osd"
  status_command "/etc/init.d/ceph status osd"
  restart_command "/etc/init.d/ceph restart osd"
end

if node[:ceph][:osd_id] && node[:ceph][:osd_id] == 0 && File.exists?("#{node[:ceph][:mount_point]}/osd.#{node[:ceph][:osd_id]}") && search(:node, 'recipes:ceph\:\:osd').size == 1 && File.read("/etc/ceph/ceph.conf").include?("[osd.#{node[:ceph][:osd_id]}]")
  
  # monmap from mon node is written to <mount_point>/ceph-stage2/monmap
  if search(:node, 'recipes:ceph\:\:mon').first[:ceph][:monmap]
    file "#{node[:ceph][:mount_point]}/ceph-stage2/monmap" do
      content Base64.decode64(search(:node, 'recipes:ceph\:\:mon').first[:ceph][:monmap])
    end
  end

  # initializing osd node (by using mkcephfs), created files: key.mds.$name and keyring.mds.$name
  # :mount_point/osd.:osd_id directory is also initialized
  execute "init osd" do
    command "mkcephfs -c /etc/ceph/ceph.conf -d #{node[:ceph][:mount_point]}/ceph-stage2 --init-local-daemons osd"
    only_if { File.exists?("#{node[:ceph][:mount_point]}/ceph-stage2/monmap") && (not File.exists?("#{node[:ceph][:mount_point]}/ceph-stage2/key.osd.#{node[:ceph][:osd_id]}")) }
    notifies :create, "ruby_block[store osd key and keyring]", :immediately
  end

  # storing key and keyring from previous recipe
  ruby_block "store osd key and keyring" do
    action :nothing
    block do
      key = Base64.encode64(File.read("#{node[:ceph][:mount_point]}/ceph-stage2/key.osd.#{node[:ceph][:osd_id]}"))
      node.set[:ceph][:osd][:key] = key
      keyring = Base64.encode64(File.read("#{node[:ceph][:mount_point]}/ceph-stage2/keyring.osd.#{node[:ceph][:osd_id]}"))
      node.set[:ceph][:osd][:keyring] = keyring
    end
    not_if { node[:ceph][:osd] }
    notifies :restart, "service[ceph-osd]" 
  end
  
elsif node[:ceph][:osd_id] && node[:ceph][:osd_id] != 0 && search(:node, 'recipe:ceph\:\:osd').size > 1 && File.read("/etc/ceph/ceph.conf").include?("[osd.#{node[:ceph][:osd_id]}]")
  # expanding cluster by new osd, mon need to be aware of new osd

  # get current monmap from mon
  execute "get monmap" do
    command "ceph mon getmap -o #{node[:ceph][:mount_point]}/ceph-stage2/monmap"
    not_if { File.exists?("#{node[:ceph][:mount_point]}/ceph-stage2/monmap") }
    notifies :run, "execute[initialize osd fs]", :immediately
  end

  # initalizing :mount_point/osd.:osd_id directory
  execute "initialize osd fs" do
    action :nothing
    command "ceph-osd -c /etc/ceph/ceph.conf -i #{node[:ceph][:osd_id]} --mkfs --monmap #{node[:ceph][:mount_point]}/ceph-stage2/monmap"
    notifies :run, "execute[create osd key and keyring]", :immediately
  end

  # creating key and keyring
  execute "create osd key and keyring" do
    action :nothing
    command "ceph-authtool --create-keyring #{node[:ceph][:mount_point]}/ceph-stage2/keyring.osd.#{node[:ceph][:osd_id]} && ceph-authtool --gen-key --caps=#{node[:ceph][:mount_point]}/ceph-stage2/caps --name=osd.#{node[:ceph][:osd_id]} #{node[:ceph][:mount_point]}/ceph-stage2/keyring.osd.#{node[:ceph][:osd_id]}"
    cwd "#{node[:ceph][:mount_point]}/ceph-stage2/"
    notifies :run, "execute[add osd to authorized machines]", :immediately
  end
  
  # adding osd to authorized machines, based on previously generated keyring
  execute "add osd to authorized machines" do
    action :nothing
    command "ceph auth add osd.#{node[:ceph][:osd_id]} osd 'allow *' mon 'allow rwx' -i #{node[:ceph][:mount_point]}/ceph-stage2/keyring.osd.#{node[:ceph][:osd_id]}"
    notifies :run, "execute[set osd count]", :immediately
  end
  
  # setting osd count at mon node
  execute "set osd count" do
    action :nothing
    command "ceph osd setmaxosd #{search(:node, 'recipe:ceph\:\:osd').size}"
    notifies :run, "execute[generate and set crushmap]", :immediately
  end

  # generating balanced crushmap
  # balanced - data are distributed evenly between osd nodes
  execute "generate and set crushmap" do
    action :nothing
    command "osdmaptool --createsimple #{search(:node, 'recipe:ceph\:\:osd').size} --clobber #{node[:ceph][:mount_point]}/ceph-stage2/osdmap.junk --export-crush #{node[:ceph][:mount_point]}/ceph-stage2/crush.new && ceph osd setcrushmap -i #{node[:ceph][:mount_point]}/ceph-stage2/crush.new"
    notifies :restart, "service[ceph-osd]"
  end

end

if node[:ceph][:osd_id]
  monitrc "ceph-osd", :template => "ceph-monit", :type => "osd", :id => node[:ceph][:osd_id]
  muninrc "ceph_client_latency", :template => "ceph-perf", :id => node[:ceph][:osd_id], :counters => "op_r_lat,op_w_lat", :label => "latency"
  muninrc "ceph_client_rw", :template => "ceph-perf", :id => node[:ceph][:osd_id], :counters => "op_r,op_w", :label => "number of ops"
  muninrc "ceph_pgs", :template => "ceph-perf", :id => node[:ceph][:osd_id], :counters => "numpg_primary,numpg_replica", :label => "pg count"
  muninrc "ceph_ops", :template => "ceph-perf", :id => node[:ceph][:osd_id], :counters => "op", :label => "numer of ops"
  muninrc "ceph_opq", :template => "ceph-perf", :id => node[:ceph][:osd_id], :counters => "opq", :label => "numer of ops"
  muninrc "ceph_hbt", :template => "ceph-perf", :id => node[:ceph][:osd_id], :counters => "hbto,hbfrom", :label => "node count"
end
