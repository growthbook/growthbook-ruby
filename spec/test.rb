require 'growthbook'

client = Growthbook::Client.new
user1 = client.user(id:"1")
user2 = client.user(id:"2")

experiment = Growthbook::Experiment.new("my-test", 2)
puts "User 1: " + user1.experiment(experiment).variation.to_s
puts "User 2: " + user2.experiment(experiment).variation.to_s
