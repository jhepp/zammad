# Copyright (C) 2012-2014 Zammad Foundation, http://zammad-foundation.org/

class ActivityStreamController < ApplicationController
  before_filter :authentication_check

  # GET /api/v1/activity_stream
  def show
    activity_stream = current_user.activity_stream( params[:limit], true )

    # return result
    render json: activity_stream
  end

end
