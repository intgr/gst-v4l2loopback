using Gst, GLib, v4lsys;

//unknown: 
//what is the differens between names in different structures?
//how are the names related to class name?
//why pad factory are static?//answer - this is just a struct used to registre pad, no need to keep a copy for every element
//how vala construction procedure maps to _base_init, _class_init and _init, when it is sayed that things in Gst element should be inited in _base_init, where are they should be in vala code?//partial answer:_base_init or _class_init is a class construct, _init is a construct
//what is the difference between plugin and element?//answer - plugin is something like class, element is instance
//when it is best to call Plugin.register_static?//ansewr - anywhere between Gst.Init and call to element factory

/** 
  Class that inherits from VideoSink. It should be easier to implement than subclassing Element.
 */
public class v4lSinkLoopback : Gst.VideoSink
{
 //must always do the same thing for an element registration, as data is cached in central registry, so function is static
 public static bool plugin_init(Plugin p) {
    //create element factory and add it to plugin p
    GLib.debug("v4lSink plugin_init");
    return Element.register(p, "v4lSinkLoopback", Rank.NONE, typeof(v4lSinkLoopback));
  }

 //must always do the same work for a plugin registration, as data is cached in central registry, so function is static
 public static void register() {
    //static registration of a plugin, so that it can be used by application only
    GLib.debug("v4lSink register");
    bool plugin_registered = Plugin.register_static(
        VERSION_MAJOR, VERSION_MINOR, "v4loopbacksink-plugin", "sink to v4l loopback device", plugin_init, "0.01",
        "LGPL", "belongs to source",  "belongs to package", "http://code.google.com/p/v4lsink/");
    assert(plugin_registered);
  }

  static const ElementDetails details = {//GstElementDetails equivalent fields are:
    "v4lSinkLoopback",//longname
    "v4lsink",//klass, whatever this means, they say look at klass-draft.txt
    "sink to v4l loopback device",//description
    "vasaka <vasaka at gmail.com>"//me
  };

  static StaticPadTemplate pad_factory;//pad factory, used to create an input pad
  private int output_fd;//output device descriptor
  private weak v4lsys.video_window vid_win;
  private weak v4lsys.video_picture vid_pic;
  private weak v4lsys.video_capability vid_caps;
  private uchar[] buffer;
  private int buffer_position;
  private int buffer_length;

  //element should not be instantiated by operator new, register it and then use ElementFactory.make, it will call construct.
  class construct  {
    GLib.debug("v4lSink construct");
    pad_factory.name_template = "sink";
    pad_factory.direction = PadDirection.SINK;//direction of the pad: can be sink, or src
    pad_factory.presence = PadPresence.ALWAYS;//when pad is available
    pad_factory.static_caps.str = "video/x-raw-rgb, width=640, height=480";//types pad accepts
    add_pad_template(pad_factory.@get());//actual pad registration, this function is inherited from Element class 
    set_details(details);//set details for v4lSinkLoopback(this klass)
  }

  construct
  {
    this.output_fd = v4lsys.open("/dev/video1", v4lsys.O_RDWR);
    assert(this.output_fd>=0); GLib.debug("device opened");
    int ret_code = v4lsys.ioctl(this.output_fd, v4lsys.VIDIOCGCAP, &this.vid_caps);
    assert(ret_code != -1); GLib.debug("got caps");
    ret_code = ioctl(this.output_fd, v4lsys.VIDIOCGPICT, &this.vid_pic);
    assert(ret_code != -1); GLib.debug("got pict");
    this.vid_pic.palette = v4lsys.VIDEO_PALETTE_RGB24;//TODO(vasaka) make configurable
    ret_code = ioctl(this.output_fd, v4lsys.VIDIOCSPICT, &this.vid_pic);
    assert(ret_code != -1); GLib.debug("set pict");
    ret_code = ioctl(this.output_fd, v4lsys.VIDIOCGWIN, &this.vid_win);
    assert(ret_code != -1); GLib.debug("got win");
    this.vid_win.width = 640;//TODO(vasaka) make configurable
    this.vid_win.height = 480;
    ret_code = ioctl(this.output_fd, v4lsys.VIDIOCSWIN, &this.vid_win);
    assert(ret_code != -1); GLib.debug("set win");

    this.buffer_length = 640*480*3;
    this.buffer_position = 0;
    this.buffer = new uint8[this.buffer_length*2];
  }

  public override Gst.FlowReturn render(Gst.Buffer buf)
  {
    stdout.printf("%u\n",buf.size);
    if (buf.size+this.buffer_position > this.buffer_length)
    {
      for(int i = 0;i<this.buffer_length-this.buffer_position;++i)
      {
        this.buffer[this.buffer_position+i] = buf.data[i];
        this.buffer[this.buffer_position+i+this.buffer_length] = buf.data[i];
      }
      for(int i=0;i<(int)buf.size - this.buffer_length + this.buffer_position;++i)
      {
        this.buffer[i] = buf.data[this.buffer_length-this.buffer_position+i];
        this.buffer[i+this.buffer_length] = buf.data[this.buffer_length-this.buffer_position+i];
      }

      v4lsys.write(this.output_fd, &this.buffer[0/*this.buffer_position*/], this.buffer_length);
      this.buffer_position = (int)buf.size - this.buffer_length + this.buffer_position;
    }
    else
    {
      for(int i = 0;i<buf.size;++i)
      {
        this.buffer[this.buffer_position+i] = buf.data[i];
        this.buffer[this.buffer_position+i+this.buffer_length] = buf.data[i];
      }
      this.buffer_position = this.buffer_position + (int)buf.size;
    }
    return Gst.FlowReturn.OK;
  }
}
}
