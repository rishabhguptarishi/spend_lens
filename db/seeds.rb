# Default categories - run with: rails db:seed
# Categories are user-specific, so we create them when a user signs up
# For now, this is a template - you can run it manually for a user:
#
# User.find_by(email: 'your@email.com').tap do |u|
#   %w[Food Travel Shopping Utilities Entertainment].each_with_index do |name, i|
#     u.categories.find_or_create_by!(name: name)
#   end
# end
