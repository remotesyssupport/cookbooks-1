module Ceph

  # checks if osd is fully configured, it works only at initial cluster node
  def osd_fullyconfigured?
    search(:node, 'recipes:ceph\:\:osd').any? { |osd| osd[:ceph][:osd] && osd[:ceph][:osd][:key] && osd[:ceph][:osd][:keyring] }
  end

  # checks if mds is fully configured, it works only at initial cluster node
  def mds_fullyconfigured?
    search(:node, 'recipes:ceph\:\:mds').any? { |mds| mds[:ceph][:mds] && mds[:ceph][:mds][:key] && mds[:ceph][:mds][:keyring] }
  end

  # functions checks if there is at least node with ceph::mon recipe completed
  def cluster_exists?
    not (search(:node, 'recipes:ceph\:\:mon').empty?)
  end

  # function returns proper string with all mons for chef-fuse 
  def get_monitors
    if cluster_exists?
      return search(:node, 'recipes:ceph\:\:mon').map { |m| m["ipaddress"] }.join(",")
    else
      nil
    end
  end

  def get_active_monitors
    out = IO.popen("ceph -s").read.match(/mons at \{(.*)\}/)
    if out.nil?
      []
    else
      mon = out[1].split(",")
      mon.map { |e| e.match(/^(.+)=/)[1] }
    end
  end

  def active_monitors_count
    get_active_monitors.size
  end
  
  def active_osds_count
    out = IO.popen("ceph -s").read.match(/(\d) osds/)

    out.nil? ? 0 : out[1].to_i
  end

  def initial_mon_exists?
    not (search(:node, 'ceph:initial_mon').empty?)
  end
  
  def get_initial_mon
    search(:node, 'ceph:initial_mon').first
  end
end
