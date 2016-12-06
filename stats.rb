require 'octokit'
require 'pp'
require 'date'
require 'time'
require 'set'
require 'logger'
require 'csv'

def token
  File.read("/Users/davidheath/.alphagov-stats-github-token").strip
end
# stack = Faraday::RackBuilder.new do |builder|
#   builder.response :logger
#   builder.use Octokit::Response::RaiseError
#   builder.adapter Faraday.default_adapter
# end
# Octokit.middleware = stack

client = Octokit::Client.new(:access_token => token)

# org = 'alphagov'
# repos = client.org_repos(org)
# repos.each do |repo|
#   puts repo.name
#   puts repo.full_name
#   stats = client.contributors_stats(repo.full_name)
#   puts stats.inspect
# end

# stats = client.code_frequency_stats('alphagov/smart-answers')
# pp stats


class Statifier
  attr_reader :client, :weeks, :logger

  def initialize(client:, logger: Logger.new(STDERR))
    @client = client
    @logger = logger
    @weeks = {}
  end

  def accumulate_repo(repo_full_name)
    logger.info repo_full_name
    stats = get_contributor_stats(repo_full_name)
    if stats.nil?
      logger.error "No stats for #{repo_full_name}"
      return
    end

    stats.each do |stats|
      total_commits = 0
      stats[:weeks].each do |week_record|
        accumulate(repo_full_name, week_record, stats[:author][:login])
        total_commits += week_record['c']
      end
      logger.info("%s: %s" % [stats[:author][:login], total_commits])
    end
  end

  def get_contributor_stats(repo_full_name)
    stats = client.contributors_stats(repo_full_name)
    i=1
    while (stats == nil) and (i <= 3)
      sleep(1)
      logger.warn "Retrying #{repo_full_name} #{i}/3"
      stats = client.contributors_stats(repo_full_name)
      i+=1
    end
    stats
  end

  def accumulate(repo_full_name, week_record, author)
    week = printable_week(week_record["w"])
    # additions = week_record['a']
    # deletions = week_record['d']
    commits = week_record['c']
    accumulate_commits(repo_full_name, week, commits)
    # accumulate_committer(repo_full_name, week, author) if commits > 0
  end

  def accumulate_commits(repo_full_name, week, commits)
    @weeks[week] ||= {}
    @weeks[week][repo_full_name] ||= {}
    @weeks[week][repo_full_name][:commits] ||= 0
    @weeks[week][repo_full_name][:commits] += commits
  end

  def accumulate_committer(repo_full_name, week, author)
    @weeks[week] ||= {}
    @weeks[week][repo_full_name] ||= {}
    @weeks[week][repo_full_name][:committers] ||= Set.new
    @weeks[week][repo_full_name][:committers] << author
  end

  def printable_week(weeknum)
    DateTime.strptime(weeknum.to_s, '%s').strftime('%Y-%m-%d')
  end

  def csv
    all_repos = @weeks.map {|w, commits_by_repo| commits_by_repo.keys}.flatten.uniq.sort
    CSV.generate do |csv|
      csv << ["Week"] + all_repos
      @weeks.each do |week, repo_map|
        csv << [week] + all_repos.map {|repo| repo_map.fetch(repo, {}).fetch(:commits, 0) }
      end
    end
  end
end

logger = Logger.new(STDERR)

s = Statifier.new(client: client, logger: logger)
client.org_repos('alphagov', :per_page => 100)
response = client.last_response
begin
  repos = response.data
  repos.each do |repo|
    puts repo.full_name
    next if repo.fork
    if repo.full_name
      s.accumulate_repo(repo.full_name)
    else
      logger.error repo.inpsect
    end
  end
  if response.rels[:next]
    response = response.rels[:next].get
  else
    response = nil
  end
end while response

puts s.csv

# {total: 1, weeks: 2, author: {}}
#     "total": 135,
#     "weeks": [
#       {
#         "w": "1367712000",
#         "a": 6898,
#         "d": 77,
#         "c": 10
#       }
#     ]

#  :author=>
#   {:login=>"leenagupte",
#    :id=>5793815,
#    :avatar_url=>"https://avatars.githubusercontent.com/u/5793815?v=3",
#    :gravatar_id=>"",
#    :url=>"https://api.github.com/users/leenagupte",
#    :html_url=>"https://github.com/leenagupte",
#    :followers_url=>"https://api.github.com/users/leenagupte/followers",
#    :following_url=>
#     "https://api.github.com/users/leenagupte/following{/other_user}",
#    :gists_url=>"https://api.github.com/users/leenagupte/gists{/gist_id}",
#    :starred_url=>
#     "https://api.github.com/users/leenagupte/starred{/owner}{/repo}",
#    :subscriptions_url=>"https://api.github.com/users/leenagupte/subscriptions",
#    :organizations_url=>"https://api.github.com/users/leenagupte/orgs",
#    :repos_url=>"https://api.github.com/users/leenagupte/repos",
#    :events_url=>"https://api.github.com/users/leenagupte/events{/privacy}",
#    :received_events_url=>
#     "https://api.github.com/users/leenagupte/received_events",
#    :type=>"User",
#    :site_admin=>false}}

