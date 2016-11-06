# == Schema Information
#
# Table name: lentil_images
#
#  id                             :integer          not null, primary key
#  description                    :text
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#  like_votes_count               :integer          default(0)
#  url                            :string(255)
#  user_id                        :integer
#  state                          :integer          default(0)
#  external_identifier            :string(255)
#  long_url                       :string(255)
#  original_metadata              :text
#  original_datetime              :datetime
#  staff_like                     :boolean          default(FALSE)
#  moderator_id                   :integer
#  moderated_at                   :datetime
#  second_moderation              :boolean          default(FALSE)
#  wins_count                     :integer          default(0)
#  losses_count                   :integer          default(0)
#  win_pct                        :float
#  popular_score                  :integer          default(0)
#  file_harvested_date            :datetime
#  file_harvest_failed            :integer          default(0)
#  donor_agreement_submitted_date :datetime
#  donor_agreement_failed         :integer          default(0)
#  failed_file_checks             :integer          default(0)
#  file_last_checked              :datetime
#  donor_agreement_rejected       :datetime
#  do_not_request_donation        :boolean
#

class Lentil::Image < ActiveRecord::Base
  stores_emoji_characters :description

  has_many :won_battles, :class_name => "Battle"
  has_many :losers, :through => :battles
  has_many :lost_battles, :class_name => "Battle", :foreign_key => "loser_id"
  has_many :winners, :through => :lost_battles, :source => :image

  has_many :like_votes
  has_many :flags

  belongs_to :user, counter_cache: true
  has_one :service, :through => :user

  has_many :taggings
  has_many :tags, :through=>:taggings

  has_many :licensings
  has_many :licenses, :through=>:licensings

  belongs_to :moderator, :class_name => Lentil::AdminUser

  default_scope { where("failed_file_checks < 3") }

  validates_uniqueness_of :external_identifier, :scope => :user_id
  validates :url, :format => URI::regexp(%w(http https))

  def self.search(page, number_to_show = nil)
    unless number_to_show.nil?
      paginate :per_page => 20, :page => page, :total_entries => number_to_show
    else
      paginate :per_page => 20, :page => page
    end
  end

  def self.recent
    order("original_datetime DESC")
  end

  def self.staff_picks
    where(:staff_like => true).order("original_datetime DESC")
  end

  def self.popular
    order("popular_score DESC").order("like_votes_count DESC")
  end

  def self.approved
    where(state: self::States[:approved]).where(:suppressed => false)
  end

  def self.approved_all
    where(state: self::States[:approved])
  end

  def self.blend
    (popular.limit(50) + recent.limit(100) + staff_picks.limit(150)).uniq.shuffle
  end

  def service_tags
    begin
      tag_ids = self.taggings.select { |tagging| tagging.staff_tag == false }.map(&:tag_id)
      tags = self.tags.select { |tag| tag_ids.include? tag.id}.sort_by(&:name)
    rescue
      Rails.logger.error "Error retrieving service_tags"
      tags = []
    end
  end

  def staff_tags
    begin
      tag_ids = self.taggings.select { |tagging| tagging.staff_tag == true }.map(&:tag_id)
      tags = self.tags.select { |tag| tag_ids.include? tag.id}.sort_by(&:name)
    rescue
      Rails.logger.error "Error retrieving staff_tags"
      tags = []
    end
  end

  def available_staff_tags(all_tags)
    tags = all_tags - (self.tags - self.staff_tags)

    if tags.length > 0
      tags = tags.sort_by(&:name)
    end
  end

  def battles
    self.won_battles + self.lost_battles
  end

  def battles_count
    self.wins_count + self.losses_count
  end

  # legacy
  def image_url
    large_url
  end

  def video_url
    https_ig_url(read_attribute(:video_url))
  end

  # legacy
  def jpeg
    large_url
  end

  def https_ig_url(my_url = url)
    if my_url.respond_to?('sub')
        # instagr.am returns 301 to instagram.com and invalid SSL certificate
        my_url.sub(/^http:/, 'https:').sub(/\/\/instagr\.am/, '//instagram.com')
    else
      my_url
    end
  end

  def large_url(https_ig = true)
    if https_ig
      https_ig_url + 'media/?size=l'
    else
      url + 'media/?size=l'
    end
  end

  def medium_url(https_ig = true)
    if https_ig
      https_ig_url + 'media/?size=m'
    else
      url + 'media/?size=m'
    end
  end

  def thumbnail_url(https_ig = true)
    if https_ig
      https_ig_url + 'media/?size=t'
    else
      url + 'media/?size=t'
    end
  end

  States = {
   :pending => 0,
   :approved => 1,
   :rejected => 2,
  }

  state_machine :state, :initial => :pending do
    States.each do |name, value|
      state name, :value => value
    end

    event :approve do
      transition all => :approved
    end

    event :reject do
      transition all => :rejected
    end
  end

  def original_metadata=(meta)
    write_attribute(:original_metadata, Oj.load(Emojimmy.emoji_to_token(meta.to_hash.to_json)))
  end

  def original_metadata
    Oj.load(Emojimmy.token_to_emoji(super.to_json))
  end

end
