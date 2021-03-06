# Jekyll plugin for fetching data from GitHub to generate more detailed views
#
# Author: Maciej Paruszewski <maciek.paruszewski@gmail.com>
# Site: http://github.com/pinoss
#
# Distributed under the MIT license
# Copyright Maciej Paruszewski 2014

module Jekyll

  class GitHubIssuesGenerator < Generator
    priority :low
    safe true

    # Generates data for pages with users key
    #
    # site - the site
    #
    # Returns nothing
    def generate(site)
      site.pages.each do |page|
        if page.data.key? 'issues'
          fetch_project_data(site, page)
        end
      end
    end

    private

    def fetch_project_data(site, page)
      require 'octokit'
      require 'json'
      require 'date'

      special_filters = site.config['issues']['special_filters'].split ' ' rescue []

      projects = page.data['issues']

      issues_labels        = []
      issues_authors       = []
      issues_assignees     = []
      issues_titles        = []
      issues_milestones    = []
      issues_filter_values = {}
      projects_data        = {}

      special_filters.each do |filter|
        issues_filter_values[filter.downcase] = []
      end

      projects.each do |project|
        issues = github_issues(project, special_filters)
        next if issues.empty?

        projects_data[project] = {}
        projects_data[project]['name'] = project
        projects_data[project]['issues'] = issues 
      
        issues_titles     += issues.map    { |issue| issue['title'] }
        issues_labels     += issues.map    { |issue| issue['labels'] }
        issues_authors    += issues.map    { |issue| issue['user_login'] }
        issues_assignees  += issues.map    { |issue| issue['assignee_login'] }
        issues_milestones += issues.select { |issue| !issue['milestone_number'].nil? }.map do |issue|
          {
            'id'           => issue['milestone_id'],
            'number'       => issue['milestone_number'],
            'state'        => issue['milestone_state'],
            'title'        => issue['milestone_title'],
            'description'  => issue['milestone_description'],
            'due_on'       => issue['milestone_due_on']
          }
        end

        special_filters.each do |filter|
          issues_filter_values[filter.downcase] += issues.map { |issue| issue['special_filter_value'][filter.downcase]['value'] }
        end
      end
      
      special_filters.each do |filter|
        issues_filter_values[filter.downcase] = {
          'name'   => filter,
          'values' => issues_filter_values[filter.downcase].flatten.compact.uniq.sort
        }
      end

      page.data['issues_titles']     = issues_titles.compact.uniq.sort.to_json
      page.data['issues_authors']    = issues_authors.compact.uniq.sort.to_json
      page.data['issues_assignees']  = issues_assignees.compact.uniq.sort.to_json
      page.data['issues_milestones'] = issues_milestones.compact.uniq.sort_by { |milestone| milestone['number'] }
      page.data['issues_labels']     = issues_labels.compact.flatten.uniq.sort_by { |label| [label['color'], label['name']] }
      page.data['issues_data']       = projects_data

      page.data['issues_special_filters'] = issues_filter_values
    end

    def github_issues(project, special_filters = [])
      result = []

      page = 1
      data = []
      begin
        data = get_data(:issues, project, page: page)
        page += 1

        result += data
      end while !data.nil? and !data.empty?

      result.map { |issue| parse_issue(issue, special_filters) }
    end

    def parse_issue(issue, special_filters = [])
      result = {}

      result['user_avatar'] = issue[:user][:avatar_url]
      result['user_login']  = issue[:user][:login]
      result['user_url']    = issue[:user][:html_url]
      
      unless issue[:assignee].nil?
        result['assignee_avatar'] = issue[:assignee][:avatar_url]
        result['assignee_login']  = issue[:assignee][:login]
        result['assignee_url']    = issue[:assignee][:html_url]
      end

      unless issue[:milestone].nil?
        result['milestone_id']          = issue[:milestone][:id]
        result['milestone_number']      = issue[:milestone][:number]
        result['milestone_state']       = issue[:milestone][:state]
        result['milestone_title']       = issue[:milestone][:title]
        result['milestone_description'] = issue[:milestone][:description]
        result['milestone_due_on']      = issue[:milestone][:due_on]
      end

      labels = issue[:labels].map do |label|
        {
          'name'  => label[:name],
          'color' => label[:color].downcase
        }
      end


      special_filter_value = {}
      special_filters.each do |filter|
        filter_regex =  /\A(#{filter})\s*\-\s*(.+)\z/i
        special_labels = labels.select { |label| label['name'] =~ filter_regex }

        if special_labels.empty?
          special_filter_value[filter.downcase] = {
            'name'  => filter,
            'value' => nil
          }
        else
          value = special_labels.map { |special_label| special_label['name'][filter_regex, 2] }
          special_filter_value[filter.downcase] = {
            'name'  => filter,
            'value' => value
          }

          labels.delete_if { |label| label['name'] =~ filter_regex }
        end

      end

      result['labels']    = labels
      result['special_filter_value'] = special_filter_value

      result['number']    = issue[:number]
      result['title']     = issue[:title]
      result['state']     = issue[:state]
      result['date']      = issue[:created_at]
      result['closed_at'] = issue[:closed_at]
      result['url']       = issue[:html_url]
      result['body']      = issue[:body]

      result
    end

    def client
      @client ||= Octokit::Client.new \
        :login    => ENV['OCTOKIT_LOGIN'],
        :password => ENV['OCTOKIT_PASWD']
    end

    def get_data(type, project, opts = {})
      result = nil

      5.times do
        result = client.send(type, project, opts)
        return result unless result.nil?

        sleep 1 
      end

      result
    end

  end
end
