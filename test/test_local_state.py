#!/usr/bin/env python
# Programmer: Chris Bunch (chris@appscale.com)


# General-purpose Python library imports
import os
import sys
import unittest


# Third party testing libraries
from flexmock import flexmock


# AppScale import, the library that we're testing here
lib = os.path.dirname(__file__) + os.sep + ".." + os.sep + "lib"
sys.path.append(lib)
from custom_exceptions import BadConfigurationException
from local_state import LocalState
from node_layout import NodeLayout


class TestLocalState(unittest.TestCase):


  def setUp(self):
    # set up a mock here to avoid making every test do it
    flexmock(os)
    flexmock(os.path)
    os.path.should_call('exists')

    self.keyname = "booscale"
    self.locations_yaml = LocalState.LOCAL_APPSCALE_PATH + "locations-" + \
      self.keyname + ".yaml"


  def test_make_appscale_directory_creation(self):
    # let's say that our ~/.appscale directory
    # does not exist
    os.path.should_receive('exists') \
      .with_args(LocalState.LOCAL_APPSCALE_PATH) \
      .and_return(False) \
      .once()

    # thus, mock out making the appscale dir
    os.should_receive('mkdir') \
      .with_args(LocalState.LOCAL_APPSCALE_PATH) \
      .and_return()

    LocalState.make_appscale_directory()


  def test_ensure_appscale_isnt_running_but_it_is(self):
    # if there is a locations.yaml file and force isn't set,
    # we should abort
    os.path.should_receive('exists').with_args(self.locations_yaml) \
      .and_return(True)

    self.assertRaises(BadConfigurationException,
      LocalState.ensure_appscale_isnt_running, self.keyname,
      False)


  def test_ensure_appscale_isnt_running_but_it_is_w_force(self):
    # if there is a locations.yaml file and force is set,
    # we shouldn't abort
    os.path.should_receive('exists').with_args(self.locations_yaml) \
      .and_return(True)

    LocalState.ensure_appscale_isnt_running(self.keyname, True)


  def test_ensure_appscale_isnt_running_and_it_isnt(self):
    # if there isn't a locations.yaml file, we're good to go
    os.path.should_receive('exists').with_args(self.locations_yaml) \
      .and_return(False)

    LocalState.ensure_appscale_isnt_running(self.keyname, False)


  def test_generate_deployment_params(self):
    # this method is fairly light, so just make sure that it constructs the dict
    # to send to the AppController correctly
    options = flexmock(name='options', table='cassandra', keyname='boo',
      appengine='1', autoscale=False, group='bazgroup',
      infrastructure='ec2', machine='ami-ABCDEFG', instance_type='m1.large')
    node_layout = NodeLayout({
      'table' : 'cassandra',
      'infrastructure' : "ec2",
      'min' : 2,
      'max' : 2
    })

    expected = {
      'table' : 'cassandra',
      'hostname' : 'public1',
      'ips' : {'node-1': ['rabbitmq_slave', 'database', 'rabbitmq', 'memcache',
        'db_slave', 'appengine']},
      'keyname' : 'boo',
      'replication' : '2',
      'appengine' : '1',
      'autoscale' : 'False',
      'group' : 'bazgroup',
      'machine' : 'ami-ABCDEFG',
      'infrastructure' : 'ec2',
      'instance_type' : 'm1.large',
      'min_images' : 2,
      'max_images' : 2
    }
    actual = LocalState.generate_deployment_params(options, node_layout,
      'public1')
    self.assertEquals(expected, actual)
